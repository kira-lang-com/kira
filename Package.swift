// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kira",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KiraCompiler", targets: ["KiraCompiler"]),
        .library(name: "KiraVM", targets: ["KiraVM"]),
        .executable(name: "kira", targets: ["KiraCLI"]),
        .executable(name: "kira-lsp", targets: ["KiraLSP"]),
    ],
    dependencies: [],
    targets: makeTargets()
)

func makeTargets() -> [Target] {
    var targets: [Target] = []

    var compilerDeps: [Target.Dependency] = [
        "KiraStdlib",
    ]
    var vmDeps: [Target.Dependency] = []

    #if !os(Windows)
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
            name: "KiraCompiler",
            dependencies: compilerDeps,
            path: "Sources/KiraCompiler"
        ),
        .target(
            name: "KiraVM",
            dependencies: vmDeps,
            path: "Sources/KiraVM"
        ),
        .executableTarget(
            name: "KiraCLI",
            dependencies: [
                "KiraCompiler",
                "KiraVM",
                "KiraStdlib",
            ],
            path: "Sources/KiraCLI"
        ),
        .executableTarget(
            name: "KiraLSP",
            dependencies: [
                "KiraCompiler",
            ],
            path: "KiraLSP/Sources/KiraLSP"
        ),
        .testTarget(
            name: "KiraCompilerTests",
            dependencies: ["KiraCompiler"],
            path: "Tests/KiraCompilerTests"
        ),
        .testTarget(
            name: "KiraVMTests",
            dependencies: ["KiraVM", "KiraCompiler"],
            path: "Tests/KiraVMTests"
        ),
        .testTarget(
            name: "KiraIntegrationTests",
            dependencies: ["KiraCompiler", "KiraVM"],
            path: "Tests/KiraIntegrationTests"
        ),
    ])

    return targets
}
