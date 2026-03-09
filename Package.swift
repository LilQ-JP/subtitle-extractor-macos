// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SubtitleExtractorMacApp",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "SubtitleExtractorMacApp",
            targets: ["SubtitleExtractorMacApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SubtitleExtractorMacApp",
            path: "Sources/SubtitleExtractorMacApp",
            resources: [
                .copy("Resources/Python"),
            ]
        ),
        .testTarget(
            name: "SubtitleExtractorMacAppTests",
            dependencies: ["SubtitleExtractorMacApp"],
            path: "Tests/SubtitleExtractorMacAppTests"
        ),
    ]
)
