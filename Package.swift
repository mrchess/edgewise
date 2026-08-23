// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Edgewise",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EdgewiseCore", targets: ["EdgewiseCore"]),
        .executable(name: "edgewised", targets: ["EdgewiseDaemon"]),
        .executable(name: "edgewise-diag", targets: ["edgewise-diag"]),
        .executable(name: "EdgewiseApp", targets: ["EdgewiseApp"]),
    ],
    targets: [
        .target(name: "EdgewiseCore"),
        .executableTarget(name: "EdgewiseDaemon", dependencies: ["EdgewiseCore"]),
        .executableTarget(name: "edgewise-diag", dependencies: ["EdgewiseCore"]),
        .executableTarget(name: "EdgewiseApp", dependencies: ["EdgewiseCore"]),
        .testTarget(name: "EdgewiseCoreTests", dependencies: ["EdgewiseCore"]),
    ]
)
