import SwiftUI
import AppKit
import WorkbenchCore

struct LayoutPanel: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("窗口布局").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "display").foregroundStyle(Theme.muted)
                }
                preview.frame(height: 158)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(LayoutPreset.allCases) { preset in
                        Button { store.setPreset(preset) } label: {
                            VStack(spacing: 7) {
                                Image(systemName: preset.symbol).font(.system(size: 19))
                                Text(preset.title).font(.system(size: 9, weight: .medium))
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(store.preset == preset ? Theme.accent : Theme.muted)
                                .background(store.preset == preset ? Theme.accent.opacity(0.07) : Theme.background,
                                            in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                                    store.preset == preset ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1))
                        }.disabled(store.isBusy)
                    }
                }
                Divider().overlay(Theme.border)
                VStack(spacing: 10) {
                    ForEach(0..<store.preset.slotCount, id: \.self) { index in slotPicker(index) }
                }
                HStack {
                    Text("显示器").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer()
                    Picker("显示器", selection: $store.selectedScreen) {
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                            Text(screen.localizedName).tag(index)
                        }
                    }.labelsHidden().frame(maxWidth: 178)
                }
                HStack {
                    Text("窗口间距").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Slider(value: Binding(get: { store.configuration.gap }, set: { store.setGap($0) }), in: 0...32, step: 4)
                    Text("\(Int(store.configuration.gap))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                        .frame(width: 18)
                }
                PrimaryButton(title: store.isBusy ? "正在准备…" : "启动并应用布局",
                    disabled: store.isBusy || store.slots.contains("")) { Task { await store.applyCurrent() } }
            }
        }
    }
    private func slotPicker(_ index: Int) -> some View {
        let id = store.slots[index]
        let app = store.favorites.first { $0.id == id }
        return HStack(spacing: 10) {
            Text(store.preset.slotLabels[index]).font(.system(size: 10)).foregroundStyle(Theme.muted).frame(width: 30, alignment: .leading)
            Menu {
                Button("暂不选择") { store.setSlot(index, appID: "") }
                ForEach(store.favorites) { entry in
                    Button(entry.name) { store.setSlot(index, appID: entry.id) }
                }
            } label: {
                HStack(spacing: 9) {
                    AppIcon(app: app, size: 22)
                    Text(app?.name ?? "选择应用").font(.system(size: 11)).foregroundStyle(app == nil ? Theme.muted : Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(Theme.muted)
                }.padding(9).background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            }.menuStyle(.borderlessButton).disabled(store.isBusy).accessibilityLabel("选择\(store.preset.slotLabels[index])应用")
        }
    }
    private var preview: some View {
        GeometryReader { proxy in
            let canvas = CGRect(origin: .zero, size: proxy.size)
            let frames = (try? LayoutGeometry.frames(for: store.preset, in: canvas, gap: 6, margin: 10)) ?? []
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11).fill(Theme.sidebar)
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    let app = store.favorites.first { $0.id == store.slots[index] }
                    VStack(spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.25)).frame(width: 3, height: 3) }
                            Spacer()
                        }.padding(.horizontal, 8).padding(.top, 7)
                        Spacer(minLength: 0)
                        AppIcon(app: app, size: store.preset == .grid ? 22 : 31)
                        Text(app?.name ?? store.preset.slotLabels[index]).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .background(Theme.accent.opacity(index % 2 == 0 ? 0.4 : 0.22), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.15), lineWidth: 1))
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }.accessibilityLabel("\(store.preset.title)布局预览")
    }
}
