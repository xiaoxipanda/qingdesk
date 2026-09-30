import Foundation
import WorkbenchCore

func errorObject(_ error: Error) -> [String: Any] {
    ["ok": false, "code": (error as? WorkbenchFailure)?.code ?? "connection_failed", "error": error.localizedDescription]
}

func appURL() -> URL? {
    if let index = CommandLine.arguments.firstIndex(of: "--app"), CommandLine.arguments.indices.contains(index + 1) {
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
    if let path = ProcessInfo.processInfo.environment["WORKBENCH_APP_PATH"] { return URL(fileURLWithPath: path) }
    let bundled = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return bundled.pathExtension == "app" ? bundled : nil
}

func callWorkbench(_ name: String, arguments: [String: Any]) -> [String: Any] {
    do {
        if let message = MCPProtocolServer.validateToolCall(name, arguments: arguments) {
            throw WorkbenchFailure("invalid_arguments", message)
        }
        let request = try JSONSerialization.data(withJSONObject: ["tool": name, "arguments": arguments])
        let response: Data
        do { response = try LocalControlClient.request(request) }
        catch {
            // A lost response does not imply a failed operation. Never replay a posted mutation.
            guard (error as? WorkbenchFailure)?.code == "workbench_unavailable",
                  !CommandLine.arguments.contains("--no-autostart"),
                  let url = appURL(), Bundle(url: url)?.bundleIdentifier == "local.desktop-workbench" else { throw error }
            let launch = Process()
            launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launch.arguments = ["-g", url.path]
            launch.standardOutput = FileHandle.standardError
            launch.standardError = FileHandle.standardError
            try launch.run(); launch.waitUntilExit()
            guard launch.terminationStatus == 0 else { throw error }
            var received: Data?
            for _ in 0..<20 {
                if let value = try? LocalControlClient.request(request) { received = value; break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            guard let received else {
                throw WorkbenchFailure("workbench_unavailable", "请打开「轻桌」，并检查本地控制服务是否已启动。")
            }
            response = received
        }
        guard let result = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw WorkbenchFailure("invalid_response", "工作台返回了无效响应。")
        }
        return result
    } catch { return errorObject(error) }
}

func emit(_ data: Data) { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([0x0a])) }

if let index = CommandLine.arguments.firstIndex(of: "--call"), CommandLine.arguments.indices.contains(index + 1) {
    let name = CommandLine.arguments[index + 1]
    let raw = CommandLine.arguments.indices.contains(index + 2) ? CommandLine.arguments[index + 2] : "{}"
    let arguments = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    guard let arguments, MCPProtocolServer.toolNames.contains(name) else {
        emit(try JSONSerialization.data(withJSONObject: ["ok": false, "code": "invalid_arguments"]))
        exit(2)
    }
    let result = callWorkbench(name, arguments: arguments)
    emit(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    exit(result["ok"] as? Bool == false ? 2 : 0)
}

let server = MCPProtocolServer()
while let line = readLine() {
    if line.utf8.count > 1_048_576 {
        emit(Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Message too large\"}}".utf8))
        continue
    }
    if let response = server.respond(to: Data(line.utf8), execute: callWorkbench) { emit(response) }
}
