import SwiftUI
import AppKit

@MainActor
final class WorkbenchAppDelegate: NSObject, NSApplicationDelegate {
    static weak var store: WorkspaceStore?
    static var showWorkspace: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { Self.store?.stopServer() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.showWorkspace?() }
        return true
    }
}

@main
@MainActor
struct DesktopWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(WorkbenchAppDelegate.self) var delegate
    @StateObject private var store = WorkspaceStore()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("轻桌", id: "workspace") {
            ContentView().environmentObject(store)
                .onAppear {
                    WorkbenchAppDelegate.store = store
                    WorkbenchAppDelegate.showWorkspace = { openWindow(id: "workspace"); NSApp.activate() }
                }
                .frame(minWidth: 800, minHeight: 660)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("显示轻桌") { openWindow(id: "workspace"); NSApp.activate() }
                    .keyboardShortcut("1", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("辅助功能设置…") { NativeDesktop.requestAccessibility() }
            }
        }
    }
}
