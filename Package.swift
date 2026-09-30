// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DesktopWorkbench", targets: ["DesktopWorkbench"]),
        .executable(name: "workbench-mcp", targets: ["WorkbenchMCP"]),
    ],
    targets: [
        .target(name: "WorkbenchCore"),
        .executableTarget(name: "DesktopWorkbench", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "WorkbenchMCP", dependencies: ["WorkbenchCore"]),
        .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
