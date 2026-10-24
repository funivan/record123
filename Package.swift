// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Record123",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Record123",
            path: "Sources/Record123"
        ),
        .testTarget(name: "Record123Tests", dependencies: ["Record123"], path: "Tests/Record123Tests")
    ]
)
