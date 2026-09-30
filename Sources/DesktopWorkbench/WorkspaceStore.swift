import AppKit
import ApplicationServices
import Combine
import WorkbenchCore

struct WorkspaceActivity: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let success: Bool
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var configuration = WorkspaceConfiguration()
    @Published private(set) var catalog: [ApplicationEntry] = []
    @Published private(set) var runningIDs: Set<String> = []
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var isBusy = false
    @Published private(set) var busyLabel = ""
    @Published private(set) var activities: [WorkspaceActivity] = []
    @Published var banner: String?
    @Published private(set) var serverReady = false
    @Published private(set) var canUndo = false
    @Published var selectedScreen = 0
    private var undoWindows: [DesktopWindow] = []
    private let server = LocalControlServer()
    private var timer: Timer?

    var favorites: [ApplicationEntry] { configuration.favorites }
    var displayName: String { configuration.displayName ?? "" }
    var uses24HourClock: Bool { configuration.uses24HourClock ?? true }
    var dockApps: [ApplicationEntry] {
        if let ids = configuration.dockAppIDs {
            return ids.compactMap { id in favorites.first { $0.id == id } }
        }
        let preferred = ["com.google.Chrome", "com.apple.Terminal", "com.apple.Notes"]
        let first = preferred.compactMap { id in favorites.first { $0.id == id } }
        return Array((first + favorites.filter { !preferred.contains($0.id) }).prefix(3))
    }
    var preset: LayoutPreset { configuration.preset }
    var slots: [String] {
        Array((configuration.slotAppIDs + Array(repeating: "", count: 4)).prefix(preset.slotCount))
    }
    var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/workbench-mcp").path }
    var hermesConfiguration: String {
        let encoded = (try? JSONSerialization.data(withJSONObject: helperPath, options: .fragmentsAllowed)) ?? Data()
        return "mcp_servers:\n  desktop_workbench:\n    command: \(String(data: encoded, encoding: .utf8) ?? "\"\"")\n    args: []\n"
    }

    init() {
        let seedDefaults = !FileManager.default.fileExists(atPath: WorkbenchPaths.configuration.path)
        do { configuration = try ConfigurationFile.load() ?? WorkspaceConfiguration() }
        catch {
            // Preserve a corrupt or newer configuration before a user makes changes.
            let backup = WorkbenchPaths.configuration.appendingPathExtension("backup-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.copyItem(at: WorkbenchPaths.configuration, to: backup)
            banner = "配置未能读取，原文件已保留。\(error.localizedDescription)"
        }
        refreshState()
        if configuration.mcpEnabled { startServer() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
        Task {
            let discovered = await Task.detached(priority: .userInitiated) { AppCatalog.discover() }.value
            catalog = discovered
            if seedDefaults && favorites.isEmpty {
                let seeds = ["com.google.Chrome", "com.electron.lark", "com.todesktop.230313mzl4w4u92",
                             "com.microsoft.VSCode", "com.apple.Notes", "com.apple.Terminal"]
                configuration.favorites = seeds.compactMap { id in discovered.first { $0.id == id } }
                if configuration.favorites.isEmpty { configuration.favorites = Array(discovered.prefix(6)) }
                configuration.slotAppIDs = Array(configuration.favorites.prefix(2).map(\.id))
                persist()
            }
        }
    }

    func refreshState() {
        accessibilityGranted = NativeDesktop.accessibilityGranted
        runningIDs = Set(favorites.filter { NativeDesktop.running($0.id) != nil }.map(\.id))
        if selectedScreen >= NSScreen.screens.count { selectedScreen = 0 }
    }
    func addFavorite(_ entry: ApplicationEntry) {
        if let index = favorites.firstIndex(where: { $0.id == entry.id }) {
            configuration.favorites[index] = entry; persist(); refreshState(); return
        }
        configuration.favorites.append(entry); persist(); refreshState()
    }
    func setDisplayName(_ name: String) { configuration.displayName = name; persist() }
    func set24HourClock(_ value: Bool) { configuration.uses24HourClock = value; persist() }
    func toggleDock(_ id: String) {
        var ids = dockApps.map(\.id)
        if ids.contains(id) { ids.removeAll { $0 == id } }
        else if ids.count < 5 { ids.append(id) }
        configuration.dockAppIDs = ids; persist()
    }
    func moveFavorite(_ id: String, offset: Int) {
        guard let index = favorites.firstIndex(where: { $0.id == id }),
              favorites.indices.contains(index + offset) else { return }
        configuration.favorites.swapAt(index, index + offset); persist()
    }
    func rescanCatalog() async {
        catalog = await Task.detached(priority: .userInitiated) { AppCatalog.discover() }.value
    }
    func removeFavorite(_ id: String) {
        configuration.favorites.removeAll { $0.id == id }
        configuration.dockAppIDs?.removeAll { $0 == id }
        configuration.slotAppIDs = configuration.slotAppIDs.map { $0 == id ? "" : $0 }
        // Saved scenes are retained; missing applications are explained when a scene is opened.
        persist(); refreshState()
    }
    func setPreset(_ preset: LayoutPreset) { configuration.preset = preset; persist() }
    func setSlot(_ index: Int, appID: String) {
        while configuration.slotAppIDs.count < 4 { configuration.slotAppIDs.append("") }
        for i in configuration.slotAppIDs.indices where i != index && configuration.slotAppIDs[i] == appID {
            if !appID.isEmpty { configuration.slotAppIDs[i] = "" }
        }
        configuration.slotAppIDs[index] = appID; persist()
    }
    func setGap(_ value: Double) { configuration.gap = value; persist() }
    func setMCPEnabled(_ value: Bool) {
        configuration.mcpEnabled = value
        if value { startServer() } else { server.stop(); serverReady = false }
        persist()
    }
    func saveScene(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, slots.allSatisfy({ !$0.isEmpty }) else { return }
        configuration.scenes.append(WorkspaceScene(name: trimmed, preset: preset, appIDs: slots)); persist()
    }
    func removeScene(_ id: UUID) { configuration.scenes.removeAll { $0.id == id }; persist() }
    func loadScene(_ scene: WorkspaceScene) {
        configuration.preset = scene.preset; configuration.slotAppIDs = scene.appIDs; persist()
    }
    private func persist() {
        do { try ConfigurationFile.save(configuration) }
        catch { banner = "无法保存配置：\(error.localizedDescription)" }
    }
    private func entry(_ id: String) throws -> ApplicationEntry {
        guard let app = favorites.first(where: { $0.id == id }) else {
            throw WorkbenchFailure("app_not_allowed", "请先把应用添加到工作台的常用应用，再启动或布局。")
        }
        return app
    }
    private func begin(_ text: String) throws {
        guard !isBusy else { throw WorkbenchFailure("workspace_busy", "工作台正在执行另一个操作，请稍后再试。") }
        isBusy = true; busyLabel = text; banner = nil
    }
    private func end() { isBusy = false; busyLabel = ""; refreshState() }
    func report(_ error: Error) {
        banner = error.localizedDescription
        activities.insert(WorkspaceActivity(message: error.localizedDescription, success: false), at: 0)
        activities = Array(activities.prefix(30))
    }
    private func record(_ message: String) {
        activities.insert(WorkspaceActivity(message: message, success: true), at: 0)
        activities = Array(activities.prefix(30))
    }

    func openApp(_ id: String) async {
        do {
            let app = try entry(id)
            try begin("正在打开 \(app.name)")
            defer { end() }
            _ = try await NativeDesktop.launch(app, foreground: true)
            record("已打开 \(app.name)")
        } catch { report(error) }
    }

    private func readyApp(_ app: ApplicationEntry, deadline: Date, windowReference: String? = nil) async throws -> DesktopWindow {
        guard NativeDesktop.accessibilityGranted else {
            throw WorkbenchFailure("accessibility_required", "请在系统设置中允许「轻桌」使用辅助功能，以读取和排列窗口。")
        }
        var running = NativeDesktop.running(app.id)
        var windows = running.map { NativeDesktop.windows(for: $0) } ?? []
        if windows.isEmpty {
            busyLabel = "正在启动 \(app.name)"
            running = try await NativeDesktop.launch(app, timeout: max(0.1, deadline.timeIntervalSinceNow))
        }
        while Date() < deadline {
            try Task.checkCancellation()
            if let running, !running.isTerminated {
                windows = NativeDesktop.windows(for: running)
                if !windows.isEmpty { return try NativeDesktop.selectWindow(windows, reference: windowReference) }
            }
            busyLabel = "等待 \(app.name) 的窗口"
            try await Task.sleep(for: .milliseconds(250))
            running = NativeDesktop.running(app.id)
        }
        throw WorkbenchFailure("window_timeout", "\(app.name) 已收到启动请求，但窗口尚未就绪。请在应用中打开窗口后重试。")
    }

    func ensureApp(_ id: String, timeout: Double = 15, reference: String? = nil) async throws -> [String: Any] {
        let app = try entry(id)
        try begin("正在准备 \(app.name)"); defer { end() }
        let window = try await readyApp(app, deadline: Date().addingTimeInterval(timeout), windowReference: reference)
        record("\(app.name) 的窗口已就绪")
        return ["ok": true, "app_id": app.id, "name": app.name, "pid": Int(window.pid),
                "window": window.json, "windows": NativeDesktop.running(id).map { NativeDesktop.windows(for: $0).map(\.json) } ?? []]
    }

    func applyLayout(appIDs: [String], preset: LayoutPreset, screenIndex: Int,
                     references: [String]? = nil) async throws -> [String: Any] {
        guard appIDs.count == preset.slotCount, Set(appIDs).count == appIDs.count else {
            throw WorkbenchFailure("invalid_layout", "该布局需要 \(preset.slotCount) 个不同的应用，请填满每个窗口位置。")
        }
        if let references, references.count != appIDs.count {
            throw WorkbenchFailure("invalid_arguments", "window_refs 的数量必须与 app_ids 相同。")
        }
        let apps = try appIDs.map { try entry($0) }
        guard NSScreen.screens.indices.contains(screenIndex) else { throw WorkbenchFailure("screen_missing", "所选显示器已断开。") }
        let screen = NSScreen.screens[screenIndex]
        let area = LayoutGeometry.axRect(cocoaRect: screen.visibleFrame, primaryTop: NSScreen.screens.first!.frame.maxY)
        let frames = try LayoutGeometry.frames(for: preset, in: area,
                        gap: configuration.gap, margin: configuration.margin)
        try begin("正在准备桌面布局"); defer { end() }
        let deadline = Date().addingTimeInterval(25)
        var targets: [DesktopWindow] = []
        for (index, app) in apps.enumerated() {
            targets.append(try await readyApp(app, deadline: deadline,
                windowReference: references.flatMap { $0[index].isEmpty ? nil : $0[index] }))
        }
        for window in targets { try NativeDesktop.checkResizable(window) }
        var attempted: [DesktopWindow] = []
        do {
            busyLabel = "正在排列窗口"
            for (index, window) in targets.enumerated() {
                attempted.append(window)
                try NativeDesktop.move(window, to: frames[index])
            }
            try await Task.sleep(for: .milliseconds(350))
            for (index, window) in targets.enumerated() {
                guard let actual = NativeDesktop.frame(window.element),
                      LayoutGeometry.approximatelyEqual(actual, frames[index]) else {
                    throw WorkbenchFailure("layout_size_limit", "「\(window.title)」未达到目标尺寸，可能有最小窗口尺寸限制。已尝试恢复原布局。")
                }
            }
        } catch {
            var rollbackFailed = false
            for window in attempted {
                do {
                    try NativeDesktop.move(window, to: window.frame)
                    if window.minimized {
                        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                    }
                } catch { rollbackFailed = true }
            }
            if rollbackFailed { throw WorkbenchFailure("layout_partial", "布局未完成，部分窗口无法恢复，请检查桌面后重试。") }
            throw error
        }
        undoWindows = targets; canUndo = true
        record("已应用\(preset.title) · \(apps.map(\.name).joined(separator: " + "))")
        let updated = targets.compactMap { window in
            NativeDesktop.running(window.appID).flatMap { app in NativeDesktop.windows(for: app).first { $0.id == window.id } }
        }
        return ["ok": true, "verified": true, "preset": preset.rawValue, "screen_index": screenIndex,
                "windows": updated.map(\.json)]
    }

    func restoreLayout() async throws -> [String: Any] {
        guard canUndo else { throw WorkbenchFailure("nothing_to_restore", "尚无可恢复的布局。") }
        try begin("正在恢复原布局"); defer { end() }
        for window in undoWindows {
            try NativeDesktop.move(window, to: window.frame)
            if window.minimized { AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        }
        try await Task.sleep(for: .milliseconds(250))
        guard undoWindows.allSatisfy({ window in
            NativeDesktop.frame(window.element).map { LayoutGeometry.approximatelyEqual($0, window.frame) } == true
        }) else { throw WorkbenchFailure("restore_incomplete", "部分窗口无法恢复到原尺寸，请检查桌面。") }
        canUndo = false; undoWindows = []; record("已恢复原布局")
        return ["ok": true, "verified": true]
    }

    func applyCurrent() async {
        do { _ = try await applyLayout(appIDs: slots, preset: preset, screenIndex: selectedScreen) }
        catch { report(error) }
    }
    func runScene(_ scene: WorkspaceScene) async {
        loadScene(scene)
        await applyCurrent()
    }

    func workspaceState() -> [String: Any] {
        refreshState()
        return ["accessibility_granted": accessibilityGranted, "busy": isBusy, "mcp_enabled": serverReady,
                "screens": NativeDesktop.screensJSON(), "apps": favorites.map { app in
                    let running = NativeDesktop.running(app.id)
                    return ["app_id": app.id, "name": app.name, "running": running != nil,
                            "pid": Int(running?.processIdentifier ?? 0),
                            "windows": running.map { NativeDesktop.windows(for: $0).map(\.json) } ?? []] as [String: Any]
                }, "scenes": configuration.scenes.map { ["id": $0.id.uuidString, "name": $0.name,
                        "preset": $0.preset.rawValue, "app_ids": $0.appIDs] as [String: Any] }]
    }

    private func startServer() {
        do {
            try server.start { [weak self] data, completion in
                Task { @MainActor in
                    guard let self else { completion(Data("{\"ok\":false}".utf8)); return }
                    completion(await self.handleRequest(data))
                }
            }
            serverReady = true
        } catch { serverReady = false; report(error) }
    }
    func stopServer() { server.stop() }

    private func handleRequest(_ data: Data) async -> Data {
        var response: [String: Any]
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = request["tool"] as? String else {
                throw WorkbenchFailure("invalid_arguments", "无效的工作台请求。")
            }
            let args = request["arguments"] as? [String: Any] ?? [:]
            if let issue = MCPProtocolServer.validateToolCall(action, arguments: args) {
                throw WorkbenchFailure("invalid_arguments", issue)
            }
            switch action {
            case "get_workspace_state": response = workspaceState()
            case "list_apps":
                let all = args["include_installed"] as? Bool == true
                response = ["apps": (all ? catalog : favorites).map { app in
                    ["app_id": app.id, "name": app.name, "path": app.path,
                     "favorite": favorites.contains { $0.id == app.id }, "running": NativeDesktop.running(app.id) != nil]
                }]
            case "ensure_app":
                guard let id = args["app_id"] as? String, !id.isEmpty else {
                    throw WorkbenchFailure("invalid_arguments", "缺少 app_id。")
                }
                let timeout = (args["timeout_seconds"] as? NSNumber)?.doubleValue ?? 15
                guard timeout.isFinite, timeout >= 1, timeout <= 25 else {
                    throw WorkbenchFailure("invalid_arguments", "timeout_seconds 必须在 1–25 秒之间。")
                }
                response = try await ensureApp(id, timeout: timeout, reference: args["window_ref"] as? String)
            case "apply_layout":
                guard let ids = args["app_ids"] as? [String],
                      let raw = args["preset"] as? String, let preset = LayoutPreset(rawValue: raw) else {
                    throw WorkbenchFailure("invalid_arguments", "需要 app_ids 和有效的 preset。")
                }
                response = try await applyLayout(appIDs: ids, preset: preset,
                    screenIndex: (args["screen_index"] as? Int) ?? 0, references: args["window_refs"] as? [String])
            case "launch_scene":
                guard let id = args["scene_id"] as? String,
                      let scene = configuration.scenes.first(where: { $0.id.uuidString == id }) else {
                    throw WorkbenchFailure("scene_missing", "找不到场景，请先查询 get_workspace_state。")
                }
                response = try await applyLayout(appIDs: scene.appIDs, preset: scene.preset,
                    screenIndex: (args["screen_index"] as? Int) ?? 0)
            case "restore_layout": response = try await restoreLayout()
            default: throw WorkbenchFailure("unknown_tool", "未知的工作台工具。")
            }
            response["ok"] = true
        } catch {
            if (error as? WorkbenchFailure)?.code != "workspace_busy" { report(error) }
            response = ["ok": false, "code": (error as? WorkbenchFailure)?.code ?? "operation_failed",
                        "error": error.localizedDescription]
        }
        return (try? JSONSerialization.data(withJSONObject: response, options: .sortedKeys)) ?? Data("{\"ok\":false}".utf8)
    }
}
