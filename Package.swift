// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PiaoPal",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PiaoPal", targets: ["PiaoPal"])
    ],
    targets: [
        .executableTarget(
            name: "PiaoPal",
            path: ".",
            exclude: [
                "Engine/Render/Shader.metal", "Tools", "Tests", "artwork", "docs",
                "releases", "scripts", "build", "dist", "PiaoPal.xcodeproj",
                "PiaoPal.entitlements", "Info.plist", "project.yml", "README.md"
            ],
            sources: [
                "App",
                "Engine",
                "Skins",
                "Utils"
            ],
            resources: [
                .process("Resources"),
                .copy("LICENSE"),
                .copy("THIRD_PARTY_NOTICES.md")
            ],
            swiftSettings: [
                .unsafeFlags(["-O"])
            ]
        )
    ]
)
