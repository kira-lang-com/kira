// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kira.Foundation",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KiraFoundationHost", targets: ["KiraFoundationHost"])
    ],
    targets: [
        .target(
            name: "KiraFoundationHost",
            path: "Sources/Platform"
        )
    ]
)
