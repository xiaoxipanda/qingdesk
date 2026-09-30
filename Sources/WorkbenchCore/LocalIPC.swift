import Foundation
import Darwin

private func socketAddress(_ path: String) throws -> sockaddr_un {
    let utf8 = Array(path.utf8)
    var address = sockaddr_un()
    guard utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw WorkbenchFailure("socket_path", "本地连接路径过长。")
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { bytes in
        bytes.initializeMemory(as: UInt8.self, repeating: 0)
        bytes.copyBytes(from: utf8)
    }
    return address
}

private func configureSocket(_ fd: Int32, seconds: Int) {
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
}

private func writeFrame(_ data: Data, to fd: Int32) throws {
    var frame = data; frame.append(0x0a)
    try frame.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let sent = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if sent < 0 && errno == EINTR { continue }
            guard sent > 0 else { throw WorkbenchFailure("connection_closed", "工作台连接已关闭。") }
            offset += sent
        }
    }
}

private final class ResponseBox {
    private let lock = NSLock()
    private var value: Data?
    func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
    func get() -> Data? { lock.lock(); defer { lock.unlock() }; return value }
}

private func readFrame(from fd: Int32) throws -> Data {
    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while data.count <= 1_048_576 {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw WorkbenchFailure("connection_timeout", "工作台未响应，请检查它是否正在运行。") }
        if let end = buffer[..<count].firstIndex(of: 0x0a) {
            data.append(contentsOf: buffer[..<end]); return data
        }
        data.append(contentsOf: buffer[..<count])
    }
    throw WorkbenchFailure("message_too_large", "本地请求超过大小限制。")
}

/// Local, same-user Unix socket. It exposes no TCP port or web endpoint.
public final class LocalControlServer {
    private var descriptor: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var path: String?
    private let queue = DispatchQueue(label: "workbench.ipc.accept", qos: .utility)
    public init() {}

    public func start(path: String = WorkbenchPaths.socketPath,
                      handler: @escaping (Data, @escaping (Data) -> Void) -> Void) throws {
        guard descriptor < 0 else { return }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
        let lock = Darwin.open(path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw WorkbenchFailure("socket_lock", "无法创建工作台连接锁。") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lock)
            throw WorkbenchFailure("already_running", "另一个工作台实例正在运行。")
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { Darwin.close(lock); throw WorkbenchFailure("socket_create", "无法创建本地连接。") }
        do {
            var address = try socketAddress(path)
            unlink(path)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, Darwin.listen(fd, 8) == 0 else {
                throw WorkbenchFailure("socket_bind", "无法启动本地工作台服务。")
            }
            chmod(path, 0o600)
            descriptor = fd; lockDescriptor = lock; self.path = path
            queue.async {
                while true {
                    let client = Darwin.accept(fd, nil, nil)
                    if client < 0 { if errno == EINTR { continue }; break }
                    DispatchQueue.global(qos: .utility).async {
                        defer { Darwin.close(client) }
                        var uid = uid_t(0), gid = gid_t(0)
                        guard getpeereid(client, &uid, &gid) == 0, uid == geteuid() else { return }
                        configureSocket(client, seconds: 40)
                        do {
                            let data = try readFrame(from: client)
                            let completed = DispatchSemaphore(value: 0)
                            let response = ResponseBox()
                            // Only the accept worker writes: late callbacks cannot use a closed descriptor.
                            handler(data) { value in response.set(value); completed.signal() }
                            if completed.wait(timeout: .now() + 40) == .success, let data = response.get() {
                                try writeFrame(data, to: client)
                            }
                        } catch { }
                    }
                }
            }
        } catch { Darwin.close(fd); Darwin.close(lock); throw error }
    }

    public func stop() {
        guard descriptor >= 0 else { return }
        shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor); descriptor = -1
        if let path { unlink(path) }; self.path = nil
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor); lockDescriptor = -1 }
    }
    deinit { stop() }
}

public enum LocalControlClient {
    public static func request(_ request: Data, path: String = WorkbenchPaths.socketPath, timeout: Int = 40) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WorkbenchFailure("socket_create", "无法创建本地连接。") }
        defer { Darwin.close(fd) }
        configureSocket(fd, seconds: timeout)
        var address = try socketAddress(path)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw WorkbenchFailure("workbench_unavailable", "轻桌未运行，或本地控制服务未启动。")
        }
        try writeFrame(request, to: fd)
        return try readFrame(from: fd)
    }
}
