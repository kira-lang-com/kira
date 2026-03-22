// swift-tools-version: 5.9
import PackageDescription
import Foundation

let enableWindowsLibffi = ProcessInfo.processInfo.environment["KIRA_WINDOWS_LIBFFI"] == "1"
let packageRoot = URL(fileURLWithPath: #file).deletingLastPathComponent()
let windowsLibffiLibPath = packageRoot.appendingPathComponent("Sources/ClibffiWindows/lib").path
let windowsLibffiLinkerSettings: [LinkerSetting] = enableWindowsLibffi
    ? [
        .unsafeFlags(
            ["-Xlinker", "/LIBPATH:\(windowsLibffiLibPath)", "-Xlinker", "libffi-8.lib"],
            .when(platforms: [.windows])
        )
    ]
    : []

let package = Package(
    name: "Kira",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "KiraCompiler", targets: ["KiraCompiler"]),
        .library(name: "KiraVM", targets: ["KiraVM"]),
        .executable(name: "kira", targets: ["KiraCLI"]),
        .executable(name: "kira-lsp", targets: ["KiraLSP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.0.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
    ],
    targets: makeTargets()
)

func makeTargets() -> [Target] {
    var targets: [Target] = []

    var compilerDeps: [Target.Dependency] = [
        "KiraStdlib",
        "KiraDebugRuntime",
    ]
    var vmDeps: [Target.Dependency] = ["KiraDebugRuntime"]

    #if os(Windows)
    if enableWindowsLibffi {
        targets.append(.systemLibrary(
            name: "Clibffi",
            path: "Sources/ClibffiWindows"
        ))
        compilerDeps.append("Clibffi")
        vmDeps.append("Clibffi")
    }
    #else
    targets.append(.systemLibrary(
        name: "Clibffi",
        path: "Sources/Clibffi",
        pkgConfig: "libffi",
        providers: [
            .brew(["libffi"]),
            .apt(["libffi-dev"])
        ]
    ))
    compilerDeps.append("Clibffi")
    vmDeps.append("Clibffi")

    targets.append(.systemLibrary(
        name: "Clibclang",
        path: "Sources/Clibclang",
        pkgConfig: "libclang",
        providers: [
            .brew(["llvm"]),
            .apt(["libclang-dev"])
        ]
    ))
    compilerDeps.append("Clibclang")
    #endif

    targets.append(contentsOf: [
        .target(
            name: "KiraStdlib",
            path: "Sources/KiraStdlib",
            resources: [
                .copy("Core/Primitives.kira"),
                .copy("Core/Collections.kira"),
                .copy("Core/Optional.kira"),
                .copy("Core/Result.kira"),
                .copy("Core/Range.kira"),
                .copy("Math/Vectors.kira"),
                .copy("Math/Matrices.kira"),
                .copy("Math/Quaternion.kira"),
                .copy("Math/Math.kira"),
                .copy("CTypes/CTypes.kira"),
                .copy("CTypes/CString.kira"),
                .copy("Fondation/Color.kira"),
            ]
        ),
        .target(
            name: "KiraDebugRuntime",
            path: "Sources/KiraDebugRuntime"
        ),
        .target(
            name: "KiraCompiler",
            dependencies: compilerDeps,
            path: "Sources/KiraCompiler",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .target(
            name: "KiraVM",
            dependencies: vmDeps,
            path: "Sources/KiraVM",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .target(
            name: "KiraPlatform",
            dependencies: [
                "KiraCompiler",
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ],
            path: "Sources/KiraPlatform",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .executableTarget(
            name: "KiraCLI",
            dependencies: [
                "KiraCompiler",
                "KiraPlatform",
                "KiraVM",
                "KiraStdlib",
            ],
            path: "Sources/KiraCLI",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .executableTarget(
            name: "KiraLSP",
            dependencies: [
                "KiraCompiler",
            ],
            path: "KiraLSP/Sources/KiraLSP",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .testTarget(
            name: "KiraCompilerTests",
            dependencies: ["KiraCompiler", "KiraDebugRuntime"],
            path: "Tests/KiraCompilerTests",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .testTarget(
            name: "KiraVMTests",
            dependencies: ["KiraVM", "KiraCompiler", "KiraDebugRuntime"],
            path: "Tests/KiraVMTests",
            linkerSettings: windowsLibffiLinkerSettings
        ),
        .testTarget(
            name: "KiraIntegrationTests",
            dependencies: ["KiraCompiler", "KiraVM"],
            path: "Tests/KiraIntegrationTests",
            linkerSettings: windowsLibffiLinkerSettings
        ),
    ])

    return targets
}
