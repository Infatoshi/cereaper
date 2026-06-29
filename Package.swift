// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cereaper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cereaper",
            path: "Sources/Cereaper"
        ),
        .testTarget(
            name: "CereaperTests",
            dependencies: ["Cereaper"],
            path: "Tests/CereaperTests"
        ),
    ]
)
