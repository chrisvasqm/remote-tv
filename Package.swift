// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RemoteTV",
    platforms: [.macOS(.v14)],
    targets: [
        // Brand-neutral: the TV protocol, pairing key storage, Wake-on-LAN.
        .target(name: "RemoteTVCore"),
        // One target per brand, each implementing RemoteTVCore's TV protocol.
        .target(name: "LGWebOS", dependencies: ["RemoteTVCore"]),
        .executableTarget(name: "RemoteTV", dependencies: ["RemoteTVCore", "LGWebOS"]),
        .executableTarget(name: "lgremote-check", dependencies: ["RemoteTVCore", "LGWebOS"]),
    ]
)
