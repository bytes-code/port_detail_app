// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortDetailApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PortDetailApp",
            path: "Sources"
        )
    ]
)
