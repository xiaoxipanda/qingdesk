import SwiftUI
import AppKit
import WorkbenchCore

enum Theme {
    static let background = Color(red: 0.99, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.34, green: 0.28, blue: 0.25)
    static let clock = Color(red: 0.48, green: 0.31, blue: 0.28)
    static let muted = Color(red: 0.62, green: 0.54, blue: 0.50)
    static let accent = Color(red: 0.51, green: 0.41, blue: 0.26)
    static let border = Color(red: 0.91, green: 0.86, blue: 0.82)
    static let sidebar = Color(red: 0.25, green: 0.23, blue: 0.21)
    static let green = Color(red: 0.21, green: 0.57, blue: 0.40)
}

struct AppIcon: View {
    let app: ApplicationEntry?
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let app {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().interpolation(.high)
            } else {
                Image(systemName: "plus").resizable().scaledToFit().padding(size * 0.27)
                    .foregroundStyle(Theme.muted)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct LauncherIcon: View {
    @EnvironmentObject var store: WorkspaceStore
    let app: ApplicationEntry
    var body: some View {
        Button { Task { await store.openApp(app.id) } } label: {
            VStack(spacing: 10) {
                AppIcon(app: app, size: 48).frame(width: 72, height: 72)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 19))
                    .overlay(alignment: .bottomTrailing) {
                        if store.runningIDs.contains(app.id) {
                            Circle().fill(Theme.green).frame(width: 6, height: 6)
                                .overlay(Circle().stroke(Theme.background, lineWidth: 2)).padding(6)
                        }
                    }
                Text(app.name).font(.system(size: 12)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.center).frame(height: 30, alignment: .top)
            }.frame(width: 108)
        }.disabled(store.isBusy).help("打开\(app.name)").accessibilityLabel("打开\(app.name)")
            .accessibilityIdentifier("launcher.app.\(app.id)")
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "play.fill"
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(.white).background(Theme.accent.opacity(disabled ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(disabled)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(20).background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }
}

struct WorkbenchMascot: View {
    var body: some View {
        ZStack {
            SoftTriangle().fill(LinearGradient(colors: [Color(red: 1, green: 0.91, blue: 0.27),
                Color(red: 1, green: 0.79, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .yellow.opacity(0.18), radius: 8, y: 4)
            Image(systemName: "eyeglasses").font(.system(size: 38, weight: .regular))
                .foregroundStyle(Theme.ink).offset(y: -4)
            Path { path in
                path.move(to: CGPoint(x: 28, y: 75)); path.addLine(to: CGPoint(x: 45, y: 81))
                path.addLine(to: CGPoint(x: 28, y: 87)); path.closeSubpath()
                path.move(to: CGPoint(x: 62, y: 75)); path.addLine(to: CGPoint(x: 45, y: 81))
                path.addLine(to: CGPoint(x: 62, y: 87)); path.closeSubpath()
            }.fill(Theme.ink)
        }.accessibilityHidden(true)
    }
}

private struct SoftTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.39, y: h * 0.09))
        path.addQuadCurve(to: CGPoint(x: w * 0.64, y: h * 0.12), control: CGPoint(x: w * 0.53, y: -h * 0.06))
        path.addLine(to: CGPoint(x: w * 0.96, y: h * 0.66))
        path.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.85), control: CGPoint(x: w * 1.08, y: h * 0.87))
        path.addLine(to: CGPoint(x: w * 0.19, y: h * 0.85))
        path.addQuadCurve(to: CGPoint(x: w * 0.04, y: h * 0.65), control: CGPoint(x: -w * 0.07, y: h * 0.84))
        path.closeSubpath()
        return path
    }
}

struct WallpaperPattern: View {
    private let points: [(CGFloat, CGFloat, String, Double)] = [
        (0.08, 0.07, "leaf", -25), (0.82, 0.09, "cloud", 12), (0.22, 0.29, "leaf", 24),
        (0.92, 0.37, "sparkle", -12), (0.06, 0.50, "cloud", -14), (0.77, 0.52, "leaf", 18),
        (0.14, 0.79, "sparkle", 10), (0.89, 0.83, "leaf", -30), (0.57, 0.87, "cloud", 6),
    ]
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(points.indices, id: \.self) { index in
                    let point = points[index]
                    Image(systemName: point.2).font(.system(size: 27, weight: .ultraLight))
                        .foregroundStyle(Theme.clock.opacity(0.11)).rotationEffect(.degrees(point.3))
                        .position(x: proxy.size.width * point.0, y: proxy.size.height * point.1)
                }
            }
        }
    }
}
