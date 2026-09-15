// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StoryCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "StoryCore", targets: ["StoryCore"])],
    targets: [
        .target(name: "StoryCore", resources: [.process("Resources")]),
        .testTarget(name: "StoryCoreTests", dependencies: ["StoryCore"])
    ]
)
