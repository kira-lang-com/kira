import Foundation

public struct KiraPackage: Codable, Sendable {
    public struct Package: Codable, Sendable {
        public var name: String
        public var version: String
        public var kira: String
        public var license: String
    }

    public struct Targets: Codable, Sendable {
        public var ios: Bool = true
        public var android: Bool = true
        public var macos: Bool = true
        public var linux: Bool = true
        public var windows: Bool = true
        public var wasm: Bool = false

        public init() {}
    }

    public var package: Package
    public var targets: Targets
    public var dependencies: [String: String]
    public var build: BuildConfig

    public init(package: Package, targets: Targets = Targets(), dependencies: [String: String] = [:], build: BuildConfig = BuildConfig()) {
        self.package = package
        self.targets = targets
        self.dependencies = dependencies
        self.build = build
    }

    public static func load(from url: URL) throws -> KiraPackage {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseToml(text)
    }

    public func save(to url: URL) throws {
        try renderToml().write(to: url, atomically: true, encoding: .utf8)
    }

    private static func parseToml(_ text: String) throws -> KiraPackage {
        // Minimal TOML reader sufficient for Kira.toml as specified.
        enum Section { case none, package, targets, dependencies, build }
        var section: Section = .none

        var pkgName = "KiraProject"
        var pkgVersion = "0.1.0"
        var kiraReq = ">=1.0.0"
        var license = "Apache-2.0"

        var targets = Targets()
        var dependencies: [String: String] = [:]
        var build = BuildConfig()

        func setKV(_ key: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch section {
            case .package:
                switch key {
                case "name": pkgName = v
                case "version": pkgVersion = v
                case "kira": kiraReq = v
                case "license": license = v
                default: break
                }
            case .targets:
                let b = (v == "true")
                switch key {
                case "ios": targets.ios = b
                case "android": targets.android = b
                case "macos": targets.macos = b
                case "linux": targets.linux = b
                case "windows": targets.windows = b
                case "wasm": targets.wasm = b
                default: break
                }
            case .dependencies:
                dependencies[key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))] = v
            case .build:
                switch key {
                case "optimization":
                    build.optimization = BuildConfig.Optimization(rawValue: v) ?? .debug
                case "hotReload":
                    build.hotReload = (v == "true")
                case "incrementalBuild":
                    build.incrementalBuild = (v == "true")
                case "executionMode":
                    build.executionMode = BuildConfig.ExecutionMode(rawValue: v) ?? .hybrid
                default: break
                }
            case .none:
                break
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine
            if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let name = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                switch name {
                case "package": section = .package
                case "targets": section = .targets
                case "dependencies": section = .dependencies
                case "build": section = .build
                default: section = .none
                }
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            setKV(parts[0], parts[1])
        }

        return KiraPackage(
            package: .init(name: pkgName, version: pkgVersion, kira: kiraReq, license: license),
            targets: targets,
            dependencies: dependencies,
            build: build
        )
    }

    private func renderToml() -> String {
        var out: [String] = []
        out.append("[package]")
        out.append("name = \"\(package.name)\"")
        out.append("version = \"\(package.version)\"")
        out.append("kira = \"\(package.kira)\"")
        out.append("license = \"\(package.license)\"")
        out.append("")
        out.append("[targets]")
        out.append("ios = \(targets.ios)")
        out.append("android = \(targets.android)")
        out.append("macos = \(targets.macos)")
        out.append("linux = \(targets.linux)")
        out.append("windows = \(targets.windows)")
        out.append("wasm = \(targets.wasm)")
        out.append("")
        out.append("[dependencies]")
        for (k, v) in dependencies.sorted(by: { $0.key < $1.key }) {
            out.append("\"\(k)\" = \"\(v)\"")
        }
        out.append("")
        out.append("[build]")
        out.append("optimization = \"\(build.optimization.rawValue)\"")
        out.append("hotReload = \(build.hotReload)")
        out.append("incrementalBuild = \(build.incrementalBuild)")
        out.append("executionMode = \"\(build.executionMode.rawValue)\"")
        out.append("")
        return out.joined(separator: "\n")
    }
}
