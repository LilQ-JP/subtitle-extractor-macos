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
    dependencies: [],
    targets: [
        .target(
            name: "CaptionAppearanceBridge",
            dependencies: [],
            path: "Sources/CaptionAppearanceBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("MediaAccessibility"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "SubtitleExtractorMacApp",
            dependencies: [
                "CaptionAppearanceBridge",
            ],
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
