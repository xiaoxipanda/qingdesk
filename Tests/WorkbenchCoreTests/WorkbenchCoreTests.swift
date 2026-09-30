import XCTest
import CoreGraphics
@testable import WorkbenchCore

final class WorkbenchCoreTests: XCTestCase {
    func testLauncherOverflowHasCompleteVisiblePages() {
        let normal = LauncherGridGeometry(availableSize: CGSize(width: 952, height: 384))
        XCTAssertEqual(normal.capacity, 15)
        XCTAssertEqual(normal.pageCount(itemCount: 16), 2)
        XCTAssertEqual(normal.range(page: 0, itemCount: 16), 0..<15)
        XCTAssertEqual(normal.range(page: 1, itemCount: 16), 15..<16)
        for size in [CGSize(width: 752, height: 244), CGSize(width: 952, height: 384), CGSize(width: 1300, height: 680)] {
            let grid = LauncherGridGeometry(availableSize: size)
            XCTAssertLessThanOrEqual(grid.contentSize.width, size.width)
            XCTAssertLessThanOrEqual(grid.contentSize.height, size.height)
            let all = (0..<grid.pageCount(itemCount: 203)).flatMap { Array(grid.range(page: $0, itemCount: 203)) }
            XCTAssertEqual(all, Array(0..<203))
            XCTAssertEqual(grid.range(page: 99, itemCount: 3), 0..<3)
            XCTAssertEqual(grid.range(page: 0, itemCount: 0), 0..<0)
        }
    }
    func testLeftRightKeepsMarginsAndGapOnNegativeOriginDisplay() throws {
        let frames = try LayoutGeometry.frames(for: .leftRight, in: CGRect(x: -1440, y: 25, width: 1440, height: 875))
        XCTAssertEqual(frames[0], CGRect(x: -1428, y: 37, width: 702, height: 851))
        XCTAssertEqual(frames[1], CGRect(x: -714, y: 37, width: 702, height: 851))
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 12)
    }
    func testEveryLayoutStaysInsideUsableScreenWithoutOverlaps() throws {
        let bounds = CGRect(x: 1440, y: -900, width: 1920, height: 1050)
        for preset in LayoutPreset.allCases {
            let frames = try LayoutGeometry.frames(for: preset, in: bounds, gap: 16, margin: 20)
            XCTAssertEqual(frames.count, preset.slotCount)
            for (index, frame) in frames.enumerated() {
                XCTAssertTrue(bounds.insetBy(dx: 20, dy: 20).contains(frame))
                for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
            }
        }
    }
    func testAXConversionForDisplaysAboveAndBelowPrimary() {
        XCTAssertEqual(LayoutGeometry.axRect(cocoaRect: CGRect(x: 0, y: 900, width: 1000, height: 800), primaryTop: 900),
                       CGRect(x: 0, y: -800, width: 1000, height: 800))
        XCTAssertEqual(LayoutGeometry.axRect(cocoaRect: CGRect(x: -1000, y: -800, width: 1000, height: 800), primaryTop: 900),
                       CGRect(x: -1000, y: 900, width: 1000, height: 800))
    }
    func testInvalidGeometryIsRejected() {
        XCTAssertThrowsError(try LayoutGeometry.frames(for: .grid, in: .zero))
        XCTAssertThrowsError(try LayoutGeometry.frames(for: .leftRight, in: CGRect(x: 0, y: 0, width: 800, height: 600), gap: -1))
    }
    func testConfigurationPersistsScenesAndDoesNotResetEmptyFavorites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("workspace.json")
        var config = WorkspaceConfiguration()
        config.scenes = [WorkspaceScene(name: "资料整理", preset: .leftRight, appIDs: ["a", "b"])]
        config.mcpEnabled = false
        try ConfigurationFile.save(config, to: url)
        let loaded = try XCTUnwrap(ConfigurationFile.load(from: url))
        XCTAssertEqual(loaded.scenes, config.scenes)
        XCTAssertTrue(loaded.favorites.isEmpty)
        XCTAssertFalse(loaded.mcpEnabled)
    }

    private func call(_ server: MCPProtocolServer, _ request: [String: Any],
                      execute: (String, [String: Any]) -> [String: Any] = { _, _ in ["ok": true] }) throws -> [String: Any]? {
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let response = server.respond(to: data, execute: execute) else { return nil }
        return try JSONSerialization.jsonObject(with: response) as? [String: Any]
    }
    private func initializedServer() throws -> MCPProtocolServer {
        let server = MCPProtocolServer()
        _ = try call(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        return server
    }
    func testMCPHandshakeAndNotificationsKeepStdoutClean() throws {
        let server = try initializedServer()
        XCTAssertNil(try call(server, ["jsonrpc": "2.0", "method": "notifications/initialized"]))
        let result = try call(server, ["jsonrpc": "2.0", "id": "tools", "method": "tools/list"])?["result"] as? [String: Any]
        let tools = try XCTUnwrap(result?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), Set(MCPProtocolServer.toolNames))
    }
    func testMCPDoesNotExecuteBeforeInitializationOrWithInvalidArguments() throws {
        let cold = MCPProtocolServer()
        let coldResponse = try call(cold, ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        XCTAssertEqual((coldResponse?["error"] as? [String: Any])?["code"] as? Int, -32002)
        let server = try initializedServer()
        let bad: [[String: Any]] = [["app_id": "a", "timeout_seconds": true],
                                    ["app_id": "a", "timeout_seconds": 30], ["unexpected": "a"], ["app_id": ""]]
        for arguments in bad {
            let response = try call(server, ["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "ensure_app", "arguments": arguments]]) { _, _ in
                XCTFail("Invalid arguments reached the desktop executor"); return ["ok": true]
            }
            XCTAssertEqual((response?["error"] as? [String: Any])?["code"] as? Int, -32602)
        }
    }
    func testMCPReportsOperationFailureAsToolErrorAndStructuredData() throws {
        let server = try initializedServer()
        let response = try call(server, ["jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "ensure_app", "arguments": ["app_id": "a"]]]) { _, _ in
            ["ok": false, "code": "window_timeout", "error": "Window did not appear"]
        }
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual((result["structuredContent"] as? [String: Any])?["code"] as? String, "window_timeout")
    }
    func testMalformedJSONIsAProtocolError() throws {
        let response = MCPProtocolServer().respond(to: Data("{".utf8)) { _, _ in XCTFail(); return [:] }
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(response)) as! [String: Any]
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? Int, -32700)
    }
    func testLocalTransportPreservesFramesAndRejectsSecondServer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wb-\(UUID().uuidString.prefix(8))")
        let path = root.appendingPathComponent("control.sock").path
        let server = LocalControlServer(), other = LocalControlServer()
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        try server.start(path: path) { request, completion in completion(request) }
        XCTAssertThrowsError(try other.start(path: path) { _, _ in })
        let bytes = Data(String(repeating: "x", count: 12_000).utf8)
        XCTAssertEqual(try LocalControlClient.request(bytes, path: path), bytes)
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        server.stop()
        XCTAssertThrowsError(try LocalControlClient.request(bytes, path: path))
    }
}
