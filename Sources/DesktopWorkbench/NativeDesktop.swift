import AppKit
import ApplicationServices
import WorkbenchCore

private final class LaunchReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSRunningApplication, Error>?
    init(_ continuation: CheckedContinuation<NSRunningApplication, Error>) { self.continuation = continuation }
    func finish(_ result: Result<NSRunningApplication, Error>) {
        lock.lock()
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

enum AppCatalog {
    static func discover() -> [ApplicationEntry] {
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var apps: [String: ApplicationEntry] = [:]
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator {
                if iterator.level > 3 { iterator.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                iterator.skipDescendants()
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      apps[id] == nil else { continue }
                let display = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                    ?? (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                apps[id] = ApplicationEntry(id: id, name: display.replacingOccurrences(of: ".app", with: ""), path: url.path)
            }
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct DesktopWindow: Identifiable {
    let id: String
    let appID: String
    let pid: pid_t
    let nativeID: CGWindowID?
    let title: String
    let element: AXUIElement
    let frame: CGRect
    let minimized: Bool
    let focused: Bool
    var json: [String: Any] {
        var result: [String: Any] = ["window_ref": id, "app_id": appID, "pid": Int(pid),
            "title": title, "minimized": minimized, "focused": focused,
            "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]]
        if let nativeID { result["window_id"] = Int(nativeID) }
        return result
    }
}

@MainActor
enum NativeDesktop {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func running(_ id: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first { !$0.isTerminated }
    }

    static func launch(_ entry: ApplicationEntry, foreground: Bool = false, timeout: Double = 15) async throws -> NSRunningApplication {
        guard FileManager.default.fileExists(atPath: entry.path),
              Bundle(path: entry.path)?.bundleIdentifier == entry.id else {
            throw WorkbenchFailure("app_not_installed", "找不到 \(entry.name)，请重新添加应用。")
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = foreground
        options.addsToRecentItems = false
        return try await withCheckedThrowingContinuation { continuation in
            let reply = LaunchReply(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0.1, timeout)) {
                reply.finish(.failure(WorkbenchFailure("launch_timeout", "\(entry.name) 的启动响应超时，请检查应用后再试。")))
            }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: entry.path), configuration: options) { app, error in
                if let error { reply.finish(.failure(error)) }
                else if let app { reply.finish(.success(app)) }
                else { reply.finish(.failure(WorkbenchFailure("launch_failed", "无法启动 \(entry.name)。"))) }
            }
        }
    }

    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func windows(for app: NSRunningApplication) -> [DesktopWindow] {
        guard accessibilityGranted, !app.isTerminated else { return [] }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let elements = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        let focused = attribute(application, kAXFocusedWindowAttribute)
        let cgWindows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier &&
                      ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }
        return elements.compactMap { element in
            AXUIElementSetMessagingTimeout(element, 0.5)
            guard let bounds = frame(element), bounds.width > 0, bounds.height > 0 else { return nil }
            let title = attribute(element, kAXTitleAttribute) as? String ?? app.localizedName ?? "窗口"
            // Public WindowServer/AX correlation. Ambiguous matches intentionally omit window_id.
            let matches = cgWindows.filter { row in
                guard let raw = row[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                return LayoutGeometry.approximatelyEqual(rect, bounds, tolerance: 2)
            }
            let nativeID = matches.count == 1 ? (matches[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value : nil
            return DesktopWindow(id: nativeID.map { "\(app.processIdentifier):\($0)" } ?? "\(app.processIdentifier):ax:\(CFHash(element))",
                appID: app.bundleIdentifier ?? "", pid: app.processIdentifier, nativeID: nativeID,
                title: title, element: element, frame: bounds,
                minimized: attribute(element, kAXMinimizedAttribute) as? Bool ?? false,
                focused: focused.map { CFEqual($0, element) } ?? false)
        }
    }

    static func selectWindow(_ windows: [DesktopWindow], reference: String? = nil) throws -> DesktopWindow {
        if let reference {
            guard let match = windows.first(where: { $0.id == reference }) else {
                throw WorkbenchFailure("window_stale", "所选窗口已关闭或变化，请刷新窗口列表。")
            }
            return match
        }
        if windows.count == 1 { return windows[0] }
        if let focused = windows.first(where: { $0.focused }) { return focused }
        if windows.isEmpty { throw WorkbenchFailure("window_unavailable", "应用尚未创建可操作窗口。") }
        throw WorkbenchFailure("window_ambiguous", "应用有多个窗口，请先在该应用中选择目标窗口，或传入 window_ref。")
    }

    static func checkResizable(_ window: DesktopWindow) throws {
        if attribute(window.element, "AXFullScreen") as? Bool == true {
            throw WorkbenchFailure("window_fullscreen", "请先让「\(window.title)」退出全屏，再应用布局。")
        }
        for key in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window.element, key as CFString, &settable) == .success,
                  settable.boolValue else {
                throw WorkbenchFailure("window_not_resizable", "「\(window.title)」不支持系统窗口调整。")
            }
        }
    }

    static func move(_ window: DesktopWindow, to bounds: CGRect) throws {
        try checkResizable(window)
        if window.minimized {
            let result = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            guard result == .success else { throw WorkbenchFailure("restore_failed", "无法恢复「\(window.title)」。") }
        }
        var point = bounds.origin, size = bounds.size
        guard let positionValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WorkbenchFailure("invalid_geometry", "窗口尺寸无效。")
        }
        // Shrink before moving to keep oversized windows from being constrained by the screen edge.
        let sizeResult = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, positionValue)
        let finalSizeResult = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success, positionResult == .success, finalSizeResult == .success else {
            throw WorkbenchFailure("layout_failed", "系统拒绝调整「\(window.title)」。")
        }
    }

    static func screensJSON() -> [[String: Any]] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.enumerated().map { index, screen in
            let frame = LayoutGeometry.axRect(cocoaRect: screen.visibleFrame, primaryTop: top)
            return ["index": index, "name": screen.localizedName,
                    "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]]
        }
    }
}
