import AppKit

// An isolated window target for real AX integration tests. No user documents are opened.
@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var constrained = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isRight = Bundle.main.bundleIdentifier?.hasSuffix("right") == true
        let name = isRight ? "Workbench Test Right" : "Workbench Test Left"
        window = NSWindow(contentRect: NSRect(x: isRight ? 760 : 100, y: 160, width: 640, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = name
        window.minSize = NSSize(width: 180, height: 160)
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "\(name)\n\n独立测试窗口，不包含用户文档。\n⌘⇧M 可切换最小宽度限制。")
        label.alignment = .center
        label.font = .systemFont(ofSize: 20)
        label.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
        ])
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let testItem = NSMenuItem()
        let testMenu = NSMenu(title: "Test")
        let toggle = NSMenuItem(title: "Toggle minimum width", action: #selector(toggleConstraint), keyEquivalent: "m")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self
        testMenu.addItem(toggle)
        testItem.submenu = testMenu
        menu.addItem(testItem)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleConstraint() {
        constrained.toggle()
        window.minSize = NSSize(width: constrained ? 1100 : 180, height: 160)
        if constrained && window.frame.width < 1100 {
            var frame = window.frame
            frame.size.width = 1100
            window.setFrame(frame, display: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FixtureApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = FixtureDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
