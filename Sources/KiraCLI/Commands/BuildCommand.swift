import Foundation
import KiraCompiler

enum BuildCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        var target: String?
        var release = false
        while let tok = a.peek() {
            if tok == "--target" {
                _ = a.next()
                target = a.next()
            } else if tok == "--release" {
                _ = a.next()
                release = true
            } else if tok == "--help" || tok == "-h" {
                print("kira build [--target <t>] [--release]")
                return
            } else {
                throw CLIError.invalidOption(tok)
            }
        }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let manifestURL = cwd.appendingPathComponent("Kira.toml")
        let pkg = try KiraPackage.load(from: manifestURL)

        let platform = parseTarget(target) ?? defaultTargetForHost()
        let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
        let sourceFiles = try collectKiraSources(in: sourcesDir)
        guard !sourceFiles.isEmpty else {
            throw CLIError.message("No .kira sources found in Sources/")
        }

        let sources: [SourceText] = try sourceFiles.map { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return SourceText(file: url.path, text: text)
        }
        let driver = CompilerDriver()
        let output = try driver.compile(sources: sources, target: platform)

        let outDir = cwd.appendingPathComponent(".kira-build/\(pkg.package.name)/\(platformName(platform))", isDirectory: true)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        if platform.isWasm {
            let wasmURL = outDir.appendingPathComponent("\(pkg.package.name).wasm")
            try (output.wasm ?? Data()).write(to: wasmURL, options: .atomic)
            print("Wrote \(wasmURL.path)")
        } else {
            let bcURL = outDir.appendingPathComponent("\(pkg.package.name).kirbc")
            try (output.bytecode ?? Data()).write(to: bcURL, options: .atomic)
            print("Wrote \(bcURL.path)")
        }

        if release || pkg.build.optimization == .release || pkg.build.executionMode == .native {
            // Native build path is optional in this scaffold.
            print("note: native codegen requires llvm-c integration; bytecode output is still produced for tooling.")
        }
    }

    private static func parseTarget(_ s: String?) -> PlatformTarget? {
        guard let s else { return nil }
        switch s.lowercased() {
        case "ios": return .iOS(arch: .arm64)
        case "android": return .android(arch: .arm64)
        case "macos": return .macOS(arch: .arm64)
        case "linux": return .linux(arch: .x86_64)
        case "windows": return .windows(arch: .x86_64)
        case "wasm": return .wasm32
        default: return nil
        }
    }

    private static func defaultTargetForHost() -> PlatformTarget {
        #if os(macOS)
        return .macOS(arch: .arm64)
        #elseif os(Linux)
        return .linux(arch: .x86_64)
        #elseif os(Windows)
        return .windows(arch: .x86_64)
        #else
        return .macOS(arch: .arm64)
        #endif
    }

    private static func platformName(_ t: PlatformTarget) -> String {
        switch t {
        case .iOS: return "ios"
        case .android: return "android"
        case .macOS: return "macos"
        case .linux: return "linux"
        case .windows: return "windows"
        case .wasm32: return "wasm32"
        }
    }

    private static func collectKiraSources(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e {
            if u.pathExtension == "kira" {
                out.append(u)
            }
        }
        out.sort { $0.path < $1.path }
        return out
    }
}
