// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyControlCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "EasyControlCore",
            targets: ["HandTracking", "Signal", "GestureEngine", "Actions", "Capture"]
        ),
        .executable(name: "ec-probe", targets: ["ec-probe"]),
        .executable(name: "ec-extract", targets: ["ec-extract"]),
        .executable(name: "ec-replay", targets: ["ec-replay"]),
    ],
    targets: [
        .target(name: "HandTracking"),
        .target(name: "Signal", dependencies: ["HandTracking"]),
        .target(name: "GestureEngine", dependencies: ["Signal"]),
        .target(name: "Actions", dependencies: ["GestureEngine"]),
        .target(name: "Capture", dependencies: ["HandTracking"]),
        .target(name: "TestSupport", dependencies: ["HandTracking"]),
        .executableTarget(name: "ec-probe", dependencies: ["Actions"]),
        .executableTarget(name: "ec-extract", dependencies: ["Capture", "Signal"]),
        .executableTarget(name: "ec-replay", dependencies: ["GestureEngine"]),
        .testTarget(name: "HandTrackingTests", dependencies: ["HandTracking", "TestSupport"]),
        .testTarget(name: "SignalTests", dependencies: ["Signal", "TestSupport"]),
        .testTarget(name: "GestureEngineTests", dependencies: ["GestureEngine", "TestSupport"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions", "TestSupport"]),
        .testTarget(name: "CaptureTests", dependencies: ["Capture", "TestSupport"]),
    ]
)
