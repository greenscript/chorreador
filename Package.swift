// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Chorreador",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Chorreador", targets: ["Chorreador"])
    ],
    targets: [
        .executableTarget(
            name: "Chorreador",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "ChorreadorTests",
            dependencies: ["Chorreador"]
        )
    ]
)
