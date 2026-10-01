import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WorkbenchCore

struct WorkbenchSettingsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var search = ""

    private var filtered: [ApplicationEntry] {
        store.catalog.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("轻桌设置").font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            }
            Picker("设置内容", selection: $page) {
                Text("常用应用").tag(0)
                Text("分屏选项").tag(1)
            }.pickerStyle(.segmented)
            if page == 0 { applicationSettings }
            else { layoutSettings }
            if page == 1 { layoutActions }
            HStack {
                Text("设置自动保存").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                if page == 0 {
                    Button("从文件选择应用…") { selectApplications() }
                        .font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
            }
        }.padding(26).frame(width: 720, height: 590).background(Theme.background)
            .buttonStyle(.plain).tint(Theme.accent)
            .task { await store.rescanCatalog() }
    }

    private var applicationSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("称呼").font(.system(size: 12)).foregroundStyle(Theme.muted)
                TextField("可选，例如 Alfred", text: Binding(get: { store.displayName }, set: { store.setDisplayName($0) }))
                    .textFieldStyle(.roundedBorder).frame(width: 180)
                Spacer()
                Toggle("24 小时制", isOn: Binding(get: { store.uses24HourClock }, set: { store.set24HourClock($0) }))
                    .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("首页应用 · \(store.favorites.count)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    Text("星标加入底部快捷栏，最多 5 个。")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(Array(store.favorites.enumerated()), id: \.element.id) { index, app in
                                favoriteRow(app, index: index)
                            }
                            if store.favorites.isEmpty {
                                Text("从右侧选择应用").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Text("添加应用").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    TextField("搜索本机应用", text: $search).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(filtered) { app in
                                let added = store.favorites.contains { $0.id == app.id }
                                HStack(spacing: 9) {
                                    AppIcon(app: app, size: 28)
                                    Text(app.name).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Button { store.addFavorite(app) } label: {
                                        Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.system(size: 18)).foregroundStyle(added ? Theme.green : Theme.accent)
                                    }.disabled(added || store.isBusy).accessibilityLabel("添加\(app.name)")
                                }.padding(9).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
                            }
                            if filtered.isEmpty {
                                Text("没有找到应用，可从文件选择。")
                                    .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.vertical, 24)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private func favoriteRow(_ app: ApplicationEntry, index: Int) -> some View {
        let pinned = store.dockApps.contains { $0.id == app.id }
        return HStack(spacing: 7) {
            AppIcon(app: app, size: 28)
            Text(app.name).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 2)
            Button { store.moveFavorite(app.id, offset: -1) } label: {
                Image(systemName: "arrow.up").font(.system(size: 10)).frame(width: 17, height: 24)
            }.disabled(index == 0).help("上移").accessibilityLabel("上移\(app.name)")
            Button { store.moveFavorite(app.id, offset: 1) } label: {
                Image(systemName: "arrow.down").font(.system(size: 10)).frame(width: 17, height: 24)
            }.disabled(index == store.favorites.count - 1).help("下移").accessibilityLabel("下移\(app.name)")
            Button { store.toggleDock(app.id) } label: {
                Image(systemName: pinned ? "star.fill" : "star").font(.system(size: 12))
                    .foregroundStyle(pinned ? Theme.accent : Theme.muted).frame(width: 20, height: 24)
            }.disabled(!pinned && store.dockApps.count >= 5)
                .help(pinned ? "移出快捷栏" : "加入快捷栏").accessibilityLabel("\(app.name)快捷栏\(pinned ? "移除" : "添加")")
            Button { store.removeFavorite(app.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10)).frame(width: 17, height: 24)
            }.help("移出首页").accessibilityLabel("移除\(app.name)")
        }.foregroundStyle(Theme.muted).padding(8).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
            .disabled(store.isBusy)
    }

    private var layoutSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择布局和应用，再点击底部按钮执行。预览和下拉选择不会启动应用。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            if !store.accessibilityGranted {
                HStack {
                    Text("排列窗口需要 macOS 辅助功能权限。")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button("去授权") { NativeDesktop.requestAccessibility() }
                        .foregroundStyle(Theme.accent).font(.system(size: 12, weight: .medium))
                }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollView {
                LayoutPanel().frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
            }
        }
    }

    private var layoutActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.border)
            HStack(spacing: 8) {
                if store.isBusy {
                    ProgressView().controlSize(.small)
                    Text(store.busyLabel).foregroundStyle(Theme.ink)
                } else if let banner = store.banner {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(banner).foregroundStyle(Theme.ink)
                } else if let result = store.layoutResult {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    Text(result).foregroundStyle(Theme.ink)
                } else {
                    Text(store.slots.contains("") ? "请为每个窗口位置选择不同的应用。" : "将启动所选应用，并排列它们的普通窗口。")
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("layout.status")
            HStack(spacing: 14) {
                if store.canUndo {
                    Button("恢复原布局") {
                        Task { do { _ = try await store.restoreLayout() } catch { store.report(error) } }
                    }.disabled(store.isBusy).foregroundStyle(Theme.accent)
                }
                PrimaryButton(title: store.isBusy ? "正在执行…" : "启动并应用布局",
                              disabled: store.isBusy || store.slots.contains("") || !store.accessibilityGranted) {
                    Task { await store.applyCurrent() }
                }.accessibilityIdentifier("layout.apply")
            }
        }
    }

    private func selectApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            store.addFavorite(ApplicationEntry(id: id, name: url.deletingPathExtension().lastPathComponent, path: url.path))
        }
    }
}
