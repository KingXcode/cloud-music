// swift-tools-version: 5.9
// swift-tools-version 声明构建此包所需的最低 Swift 版本。

import PackageDescription

let package = Package(
    name: "folder_audio",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0")
    ],
    products: [
        .library(name: "folder-audio", targets: ["folder_audio"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "folder_audio",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
