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
            name: "KiraDebugRuntime",
            path: "Sources/KiraDebugRuntime"
        ),
        .target(
            name: "KiraVM",
            dependencies: ["Clibffi", "KiraDebugRuntime"],
            path: "Sources/KiraVM"
        ),
    ]
)