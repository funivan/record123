// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Recordy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Recordy",
            path: "Sources/Recordy"
        ),
        .testTarget(name: "RecordyTests", dependencies: ["Recordy"], path: "Tests/RecordyTests")
    ]
)
