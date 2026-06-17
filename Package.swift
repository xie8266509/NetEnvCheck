// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetEnvCheck",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NetEnvCheck", targets: ["NetEnvCheck"])
    ],
    targets: [
        .executableTarget(name: "NetEnvCheck")
    ]
)
