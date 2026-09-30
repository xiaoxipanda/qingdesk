import Foundation
import CoreFoundation

public final class MCPProtocolServer {
    private var initialized = false
    public init() {}

    public static let toolNames = ["list_apps", "ensure_app", "apply_layout", "get_workspace_state", "launch_scene", "restore_layout"]
    public static func validateToolCall(_ name: String, arguments: [String: Any]) -> String? {
        guard let tool = tools.first(where: { $0["name"] as? String == name }) else { return "Unknown tool" }
        return validate(arguments, schema: tool["inputSchema"] as! [String: Any])
    }
    public static var tools: [[String: Any]] {
        func schema(_ properties: [String: Any], _ required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        let string: [String: Any] = ["type": "string", "minLength": 1]
        let screen: [String: Any] = ["type": "integer", "minimum": 0]
        let specs: [(String, String, [String: Any], Bool)] = [
            ("list_apps", "List favorite apps (default) or installed apps. Only favorites may be launched or arranged.",
             schema(["include_installed": ["type": "boolean"]]), true),
            ("ensure_app", "Launch or reuse a favorite app and wait for a readable window. Returns pid and window_id when an exact native binding is available. Does not raise the app. Requires macOS Accessibility permission.",
             schema(["app_id": string, "timeout_seconds": ["type": "number", "minimum": 1, "maximum": 25],
                     "window_ref": string], ["app_id"]), false),
            ("apply_layout", "Prepare distinct favorite apps, arrange their selected/focused windows, then verify actual frames. Returns a failure and attempts rollback if an app rejects its size. Pass window_refs for explicit multi-window targeting.",
             schema(["app_ids": ["type": "array", "items": string, "minItems": 1, "maxItems": 4, "uniqueItems": true],
                     "preset": ["type": "string", "enum": LayoutPreset.allCases.map(\.rawValue)],
                     "screen_index": screen, "window_refs": ["type": "array", "items": ["type": "string"], "maxItems": 4]],
                    ["app_ids", "preset"]), false),
            ("get_workspace_state", "Read permissions, favorite app processes/windows, display indices, busy state and saved scenes.", schema([:]), true),
            ("launch_scene", "Prepare and apply one saved workspace scene by its exact id from get_workspace_state.",
             schema(["scene_id": string, "screen_index": screen], ["scene_id"]), false),
            ("restore_layout", "Restore window frames from before the last successful layout. Does not quit applications.", schema([:]), false),
        ]
        return specs.map { name, description, input, readOnly in
            ["name": name, "description": description, "inputSchema": input,
             "annotations": ["readOnlyHint": readOnly, "destructiveHint": false,
                             "idempotentHint": readOnly || name == "ensure_app", "openWorldHint": false]]
        }
    }

    public func respond(to data: Data, execute: (String, [String: Any]) -> [String: Any]) -> Data? {
        let request: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return error(id: NSNull(), code: -32600, message: "Invalid JSON-RPC request")
            }
            request = object
        } catch { return self.error(id: NSNull(), code: -32700, message: "Parse error") }
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return error(id: request["id"] ?? NSNull(), code: -32600, message: "Invalid JSON-RPC request")
        }
        // Notifications never produce an output line.
        guard let id = request["id"] else { return nil }
        guard id is String || (id is NSNumber && CFGetTypeID(id as! NSNumber) != CFBooleanGetTypeID()) else {
            return error(id: NSNull(), code: -32600, message: "Invalid request id")
        }
        if method == "ping" { return result(id: id, value: [:]) }
        let params = request["params"] as? [String: Any] ?? [:]
        if method == "initialize" {
            guard let requested = params["protocolVersion"] as? String else {
                return error(id: id, code: -32602, message: "protocolVersion is required")
            }
            let supported = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
            initialized = true
            return result(id: id, value: ["protocolVersion": supported.contains(requested) ? requested : "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "desktop-workbench", "version": "1.0.0"],
                "instructions": "Operate only apps added to Workbench favorites. Prepare via ensure_app, then capture the returned exact pid/window_id with Hermes computer_use. Re-read state after layout changes. On ambiguity choose an explicit window_ref; never guess."])
        }
        guard initialized else { return error(id: id, code: -32002, message: "Initialize the MCP session first") }
        switch method {
        case "tools/list": return result(id: id, value: ["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String,
                  let tool = Self.tools.first(where: { $0["name"] as? String == name }) else {
                return error(id: id, code: -32602, message: "Unknown tool")
            }
            if let raw = params["arguments"], !(raw is [String: Any]) {
                return error(id: id, code: -32602, message: "arguments must be an object")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            if let message = Self.validate(arguments, schema: tool["inputSchema"] as! [String: Any]) {
                return error(id: id, code: -32602, message: message)
            }
            let outcome = execute(name, arguments)
            let text = String(data: (try? JSONSerialization.data(withJSONObject: outcome, options: .sortedKeys)) ?? Data(), encoding: .utf8) ?? "{}"
            return result(id: id, value: ["content": [["type": "text", "text": text]],
                "structuredContent": outcome, "isError": outcome["ok"] as? Bool == false])
        default: return error(id: id, code: -32601, message: "Method not found")
        }
    }

    private static func validate(_ values: [String: Any], schema: [String: Any]) -> String? {
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        for key in schema["required"] as? [String] ?? [] where values[key] == nil { return "Missing argument: \(key)" }
        for (key, value) in values {
            guard let spec = properties[key] else { return "Unknown argument: \(key)" }
            if let issue = validateValue(value, spec: spec) { return "\(key): \(issue)" }
        }
        return nil
    }
    private static func validateValue(_ value: Any, spec: [String: Any]) -> String? {
        switch spec["type"] as? String {
        case "string":
            guard let string = value as? String else { return "expected a string" }
            if let min = spec["minLength"] as? Int, string.count < min { return "must not be empty" }
            if let choices = spec["enum"] as? [String], !choices.contains(string) { return "unsupported value" }
        case "number", "integer":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { return "expected a number" }
            if spec["type"] as? String == "integer", number.doubleValue.rounded() != number.doubleValue { return "expected an integer" }
            if let min = spec["minimum"] as? NSNumber, number.doubleValue < min.doubleValue { return "below minimum" }
            if let max = spec["maximum"] as? NSNumber, number.doubleValue > max.doubleValue { return "above maximum" }
        case "boolean":
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return "expected a boolean" }
        case "array":
            guard let array = value as? [Any] else { return "expected an array" }
            if let min = spec["minItems"] as? Int, array.count < min { return "too few entries" }
            if let max = spec["maxItems"] as? Int, array.count > max { return "too many entries" }
            if spec["uniqueItems"] as? Bool == true, let strings = array as? [String], Set(strings).count != strings.count { return "entries must be unique" }
            if let item = spec["items"] as? [String: Any] {
                for value in array { if let issue = validateValue(value, spec: item) { return issue } }
            }
        default: break
        }
        return nil
    }
    private func result(id: Any, value: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": value], options: .sortedKeys)
    }
    private func error(id: Any, code: Int, message: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id,
            "error": ["code": code, "message": message]], options: .sortedKeys)
    }
}
