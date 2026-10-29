// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyBridge",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "KeyBridge", targets: ["KeyBridge"]), .executable(name: "KeyBridgeChecks", targets: ["KeyBridgeChecks"])],
    targets: [
        .target(name: "KeyBridgeCore"),
        .executableTarget(name: "KeyBridge", dependencies: ["KeyBridgeCore"], linkerSettings: [
            .linkedFramework("AVFoundation"), .linkedFramework("CoreAudio"), .linkedFramework("AppKit"), .linkedFramework("IOKit"),
            .linkedFramework("CoreBluetooth"), .linkedFramework("Network"),
            .linkedFramework("Security"), .linkedFramework("SystemConfiguration")
        ]),
        .executableTarget(name: "KeyBridgeChecks", dependencies: ["KeyBridgeCore"], path: "Tests/KeyBridgeCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
