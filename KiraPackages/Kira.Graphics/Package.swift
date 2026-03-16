// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kira.Graphics",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KiraGraphicsHost", targets: ["KiraGraphicsHost"])
    ],
    targets: [
        .target(
            name: "KiraGraphicsHost",
            path: "Sources/Platform"
        )
    ]
)

