// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FocusCompanion", platforms: [.macOS(.v13)], products: [
    .executable(name: "FocusCompanion", targets: ["FocusCompanion"]),
    .library(name: "FocusCore", targets: ["FocusCore"])
], dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
], targets: [
    .target(name: "FocusCore"),
    .target(name: "AutomationBridge", linkerSettings: [.linkedFramework("ScriptingBridge")]),
    .executableTarget(name: "FocusCompanion", dependencies: ["FocusCore", "AutomationBridge", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ScriptingBridge"), .linkedFramework("AVFoundation"), .linkedFramework("Security"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"])
])
