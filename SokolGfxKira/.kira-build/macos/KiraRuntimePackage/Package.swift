// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KiraRuntimeSupport",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "KiraVM", targets: ["KiraVM"]),
    ],
    targets: [
        .systemLibrary(
            name: "Clibffi",
            path: "Sources/Clibffi"
        ),
        .target(
            name: "KiraVM",
            dependencies: ["Clibffi"],
            path: "Sources/KiraVM"
        ),
    ]
)