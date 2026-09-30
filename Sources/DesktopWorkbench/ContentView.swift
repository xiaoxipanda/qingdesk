import SwiftUI
import WorkbenchCore

struct ContentView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var showSettings = false
    @State private var query = ""
    @State private var page = 0
    @FocusState private var searchFocused: Bool
    private var filtered: [ApplicationEntry] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.favorites.filter { value.isEmpty || $0.name.localizedCaseInsensitiveContains(value) || $0.id.localizedCaseInsensitiveContains(value) }
    }

    var body: some View {
        ZStack {
            Theme.background
            WallpaperPattern().allowsHitTesting(false).accessibilityHidden(true)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "gearshape").font(.system(size: 12))
                            .foregroundStyle(Theme.muted).padding(.horizontal, 15).padding(.vertical, 9)
                            .background(.white.opacity(0.65), in: Capsule())
                    }.accessibilityLabel("打开轻桌设置")
                }.padding(.horizontal, 26).frame(height: 52)
                ClockGreeting(name: store.displayName, uses24HourClock: store.uses24HourClock).frame(height: 156)
                searchBar.frame(height: 56)
                GeometryReader { proxy in
                    let geometry = LauncherGridGeometry(availableSize: CGSize(width: proxy.size.width - 48, height: proxy.size.height - 44))
                    let count = geometry.pageCount(itemCount: filtered.count)
                    let current = geometry.normalizedPage(page, itemCount: filtered.count)
                    VStack(spacing: 0) {
                        if filtered.isEmpty {
                            VStack(spacing: 14) {
                                Text(store.favorites.isEmpty ? "把常用应用放到这里" : "没有找到这个应用")
                                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                                Button(store.favorites.isEmpty ? "选择应用" : "在设置中添加应用") { showSettings = true }
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(LauncherGridGeometry.cellWidth), spacing: LauncherGridGeometry.columnGap), count: geometry.columns),
                                      spacing: LauncherGridGeometry.rowGap) {
                                ForEach(Array(filtered[geometry.range(page: current, itemCount: filtered.count)])) { app in LauncherIcon(app: app) }
                            }.frame(width: geometry.contentSize.width, alignment: .top)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        pagination(current: current, count: count)
                    }.padding(.horizontal, 24)
                        .onChange(of: geometry.capacity) { _, _ in page = geometry.normalizedPage(page, itemCount: filtered.count) }
                }
                dock
            }
        }
        .ignoresSafeArea(edges: .bottom).buttonStyle(.plain).tint(Theme.accent)
        .overlay(alignment: .bottom) { statusToast.padding(.bottom, 98) }
        .sheet(isPresented: $showSettings) { WorkbenchSettingsView().environmentObject(store) }
        .onChange(of: query) { _, _ in page = 0 }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("搜索应用", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused).accessibilityLabel("搜索应用").accessibilityIdentifier("launcher.search")
                .onSubmit {
                    let matches = filtered
                    if matches.count == 1, let app = matches.first { Task { await store.openApp(app.id) } }
                }
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }.accessibilityLabel("清除应用搜索").accessibilityIdentifier("launcher.clear-search")
            }
        }.padding(.horizontal, 15).frame(width: 340, height: 38)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }

    private func pagination(current: Int, count: Int) -> some View {
        HStack(spacing: 20) {
            Button { page = max(0, current - 1) } label: { Label("上一页", systemImage: "chevron.left") }
                .disabled(current == 0).accessibilityLabel("上一页应用").accessibilityIdentifier("launcher.previous-page")
                .opacity(current == 0 ? 0.35 : 1)
            Text("\(filtered.count) 个应用  ·  \(current + 1) / \(count) 页").monospacedDigit()
                .accessibilityLabel("共 \(filtered.count) 个应用，第 \(current + 1) 页，共 \(count) 页")
            Button { page = min(count - 1, current + 1) } label: { Label("下一页", systemImage: "chevron.right") }
                .disabled(current + 1 >= count).accessibilityLabel("下一页应用").accessibilityIdentifier("launcher.next-page")
                .opacity(current + 1 >= count ? 0.35 : 1)
        }.font(.system(size: 11)).foregroundStyle(Theme.muted).frame(height: 44)
    }

    private var dock: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.39), Color(red: 0.98, green: 0.81, blue: 0.27)],
                startPoint: .top, endPoint: .bottom)
            HStack(spacing: 15) {
                ForEach(store.dockApps) { app in
                    Button { Task { await store.openApp(app.id) } } label: {
                        VStack(spacing: 4) {
                            AppIcon(app: app, size: 43)
                            Circle().fill(store.runningIDs.contains(app.id) ? Theme.ink.opacity(0.5) : .clear).frame(width: 4, height: 4)
                        }
                    }.disabled(store.isBusy).help(app.name).accessibilityLabel("快捷栏打开\(app.name)")
                }
                if store.dockApps.isEmpty {
                    Button { showSettings = true } label: {
                        Label("添加快捷应用", systemImage: "plus").font(.system(size: 12)).foregroundStyle(Theme.ink)
                    }
                }
            }.padding(.horizontal, 18).padding(.vertical, 10)
                .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 19))
        }.frame(height: 86)
    }

    @ViewBuilder private var statusToast: some View {
        if store.isBusy || store.banner != nil {
            HStack(spacing: 10) {
                if store.isBusy { ProgressView().controlSize(.small) }
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                Text(store.isBusy ? store.busyLabel : store.banner ?? "")
                    .font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(3)
                if !store.isBusy {
                    Button { store.banner = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .accessibilityLabel("关闭提示")
                }
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Theme.ink.opacity(0.08), radius: 12, y: 4).frame(maxWidth: 560).padding(.horizontal, 24)
        }
    }
}

private struct ClockGreeting: View {
    let name: String
    let uses24HourClock: Bool
    var body: some View {
        VStack(spacing: 5) {
            WorkbenchMascot().frame(width: 91, height: 93).scaleEffect(0.53).frame(width: 48, height: 49)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 3) {
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text(time(context.date)).font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                        if !uses24HourClock {
                            Text(Calendar.current.component(.hour, from: context.date) >= 12 ? "PM" : "AM")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }.foregroundStyle(Theme.clock)
                    Text(date(context.date)).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "欢迎回来" : "欢迎回来，\(name)")
                .font(.system(size: 16)).foregroundStyle(Theme.ink).padding(.top, 2)
        }
    }
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = uses24HourClock ? "HH:mm" : "h:mm"
        return formatter.string(from: date)
    }
    private func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 · EEEE"
        return formatter.string(from: date)
    }
}
