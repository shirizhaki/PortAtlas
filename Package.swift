// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortAtlas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PortAtlas", targets: ["PortAtlasApp"]),
        .library(name: "PortAtlasCore", targets: ["PortAtlasCore"]),
        .library(name: "PortAtlasHardware", targets: ["PortAtlasHardware"])
    ],
    targets: [
        .target(name: "PortAtlasCore"),
        .target(name: "PortAtlasHardware", dependencies: ["PortAtlasCore"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost"), .linkedFramework("DiskArbitration")]),
        .executableTarget(name: "PortAtlasApp", dependencies: ["PortAtlasCore", "PortAtlasHardware"]),
        .executableTarget(name: "PortAtlasDiagnostics", dependencies: ["PortAtlasCore", "PortAtlasHardware"]),
        .testTarget(name: "PortAtlasCoreTests", dependencies: ["PortAtlasCore", "PortAtlasHardware"])
    ]
)
