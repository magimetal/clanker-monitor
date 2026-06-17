// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClankerMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClankerMonitor", targets: ["ClankerMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "ClankerMonitor",
            path: "Sources/ClankerMonitor",
            exclude: ["AGENTS.md"]
        )
    ]
)
