// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SlimBladeBootlegDriver",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SlimBladeCore", targets: ["SlimBladeCore"]),
        .executable(name: "SlimBladeBootlegDriver", targets: ["SlimBladeBootlegDriver"]),
        .executable(name: "SlimBladeCoreTests", targets: ["SlimBladeCoreTests"]),
    ],
    targets: [
        .target(name: "SlimBladeCore"),
        .executableTarget(
            name: "SlimBladeBootlegDriver",
            dependencies: ["SlimBladeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "SlimBladeCoreTests",
            dependencies: ["SlimBladeCore"],
            path: "Tests/SlimBladeCoreTests"
        ),
    ]
)
