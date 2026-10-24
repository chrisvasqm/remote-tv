// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LGRemote",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LGRemoteKit"),
        .executableTarget(name: "LGRemote", dependencies: ["LGRemoteKit"]),
        .executableTarget(name: "lgremote-check", dependencies: ["LGRemoteKit"]),
    ]
)
