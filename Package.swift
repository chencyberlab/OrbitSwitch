// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OrbitSwitch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrbitSwitchCore", targets: ["OrbitSwitchCore"]),
        .executable(name: "OrbitSwitch", targets: ["OrbitSwitch"])
    ],
    targets: [
        .target(name: "OrbitSwitchCore"),
        .executableTarget(
            name: "OrbitSwitch",
            dependencies: ["OrbitSwitchCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "OrbitSwitchCoreTests", dependencies: ["OrbitSwitchCore"])
    ]
)
