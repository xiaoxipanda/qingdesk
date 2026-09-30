import Foundation

public struct ApplicationEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public init(id: String, name: String, path: String) { self.id = id; self.name = name; self.path = path }
}

public enum LayoutPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case leftRight = "left_right", topBottom = "top_bottom", focusLeft = "focus_left"
    case focusRight = "focus_right", grid, single
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .leftRight: return "左右分屏"
        case .topBottom: return "上下分屏"
        case .focusLeft: return "左侧主窗口"
        case .focusRight: return "右侧主窗口"
        case .grid: return "四宫格"
        case .single: return "铺满窗口"
        }
    }
    public var slotCount: Int { self == .grid ? 4 : self == .single ? 1 : 2 }
    public var symbol: String {
        switch self {
        case .topBottom: return "rectangle.split.1x2"
        case .grid: return "rectangle.split.2x2"
        case .single: return "rectangle"
        default: return "rectangle.split.2x1"
        }
    }
    public var slotLabels: [String] {
        switch self {
        case .topBottom: return ["上方", "下方"]
        case .grid: return ["左上", "右上", "左下", "右下"]
        case .single: return ["主窗口"]
        default: return ["左侧", "右侧"]
        }
    }
}

public struct WorkspaceScene: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var preset: LayoutPreset
    public var appIDs: [String]
    public init(id: UUID = UUID(), name: String, preset: LayoutPreset, appIDs: [String]) {
        self.id = id; self.name = name; self.preset = preset; self.appIDs = appIDs
    }
}

public struct WorkspaceConfiguration: Codable, Sendable {
    public var version = 1
    public var favorites: [ApplicationEntry] = []
    public var scenes: [WorkspaceScene] = []
    public var preset: LayoutPreset = .leftRight
    public var slotAppIDs: [String] = []
    public var gap: Double = 12
    public var margin: Double = 12
    public var mcpEnabled: Bool = true
    public var displayName: String?
    public var dockAppIDs: [String]?
    public var uses24HourClock: Bool?
    public init() {}
}

public struct WorkbenchFailure: LocalizedError {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { message }
}

public enum WorkbenchPaths {
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Desktop Workbench", isDirectory: true)
    }
    public static var configuration: URL { supportDirectory.appendingPathComponent("workspace.json") }
    public static var socketPath: String { supportDirectory.appendingPathComponent("control.sock").path }
}

public enum ConfigurationFile {
    public static func load(from url: URL = WorkbenchPaths.configuration) throws -> WorkspaceConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw WorkbenchFailure("config_version", "工作台配置版本不受支持。") }
        return value
    }
    public static func save(_ configuration: WorkspaceConfiguration, to url: URL = WorkbenchPaths.configuration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}
