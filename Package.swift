// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "macSubtitleOCR",
    platforms: [
        .macOS("13.0")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .systemLibrary(
            name: "CFFmpeg",
            pkgConfig: "libavformat libavcodec libavutil",
            providers: [
                .brew(["ffmpeg"])
            ]),
        .executableTarget(
            name: "macSubtitleOCR",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CFFmpeg"
            ]),
        .testTarget(
            name: "macSubtitleOCRTests",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "macSubtitleOCR")
            ],
            resources: [
                .process("Resources")
            ])
    ])
