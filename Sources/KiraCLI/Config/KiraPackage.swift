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

    public struct Native: Codable, Sendable {
        public var ios: ApplePlatform?
        public var macos: ApplePlatform?

        public init(ios: ApplePlatform? = nil, macos: ApplePlatform? = nil) {
            self.ios = ios
            self.macos = macos
        }
    }

    public struct ApplePlatform: Codable, Sendable {
        public struct FFIEntry: Codable, Sendable {
            public var header: String
            public var lib: String
            public var bindingsOut: String?

            public init(header: String, lib: String, bindingsOut: String? = nil) {
                self.header = header
                self.lib = lib
                self.bindingsOut = bindingsOut
            }
        }

        public struct Signing: Codable, Sendable {
            public var teamID: String
            public var bundleID: String

            public init(teamID: String = "", bundleID: String = "") {
                self.teamID = teamID
                self.bundleID = bundleID
            }
        }

        public var minimumVersion: String?
        public var deviceFamily: [String]
        public var frameworks: [String]
        public var libs: [String]
        public var headerSearchPaths: [String]
        public var pods: [String: String]
        public var ffi: [String: FFIEntry]
        public var signing: Signing?

        public init(
            minimumVersion: String? = nil,
            deviceFamily: [String] = [],
            frameworks: [String] = [],
            libs: [String] = [],
            headerSearchPaths: [String] = [],
            pods: [String: String] = [:],
            ffi: [String: FFIEntry] = [:],
            signing: Signing? = nil
        ) {
            self.minimumVersion = minimumVersion
            self.deviceFamily = deviceFamily
            self.frameworks = frameworks
            self.libs = libs
            self.headerSearchPaths = headerSearchPaths
            self.pods = pods
            self.ffi = ffi
            self.signing = signing
        }
    }

    public var package: Package
    public var targets: Targets
    public var dependencies: [String: String]
    public var build: BuildConfig
    public var native: Native?

    public init(
        package: Package,
        targets: Targets = Targets(),
        dependencies: [String: String] = [:],
        build: BuildConfig = BuildConfig(),
        native: Native? = nil
    ) {
        self.package = package
        self.targets = targets
        self.dependencies = dependencies
        self.build = build
        self.native = native
    }

    public static func load(from url: URL) throws -> KiraPackage {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseToml(text)
    }

    public func save(to url: URL) throws {
        try renderToml().write(to: url, atomically: true, encoding: .utf8)
    }

    private static func parseToml(_ text: String) throws -> KiraPackage {
        var section = ""

        var pkgName = "KiraProject"
        var pkgVersion = "0.1.0"
        var kiraReq = ">=1.0.0"
        var license = "Apache-2.0"

        var targets = Targets()
        var dependencies: [String: String] = [:]
        var build = BuildConfig()
        var native = Native()

        func parseString(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        func parseBool(_ value: String) -> Bool {
            parseString(value).lowercased() == "true"
        }

        func parseStringArray(_ value: String) -> [String] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return [] }
            let inner = String(trimmed.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            return inner
                .split(separator: ",")
                .map { parseString(String($0)) }
                .filter { !$0.isEmpty }
        }

        func parseInlineTable(_ value: String) -> [String: String] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { return [:] }
            let inner = String(trimmed.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [:]
            }

            var result: [String: String] = [:]
            for entry in inner.split(separator: ",") {
                let parts = entry.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2 else { continue }
                result[parseString(parts[0])] = parseString(parts[1])
            }
            return result
        }

        func parseKeyValue(_ line: String) -> (String, String)? {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { return nil }
            return (parseString(parts[0]), parts[1])
        }

        func mutateNativePlatform(_ keyPath: WritableKeyPath<Native, ApplePlatform?>, _ body: (inout ApplePlatform) -> Void) {
            var platform = native[keyPath: keyPath] ?? ApplePlatform()
            body(&platform)
            native[keyPath: keyPath] = platform
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                continue
            }

            guard let (key, rawValue) = parseKeyValue(trimmed) else {
                continue
            }

            switch section {
            case "package":
                let value = parseString(rawValue)
                switch key {
                case "name":
                    pkgName = value
                case "version":
                    pkgVersion = value
                case "kira":
                    kiraReq = value
                case "license":
                    license = value
                default:
                    break
                }
            case "targets":
                let value = parseBool(rawValue)
                switch key {
                case "ios":
                    targets.ios = value
                case "android":
                    targets.android = value
                case "macos":
                    targets.macos = value
                case "linux":
                    targets.linux = value
                case "windows":
                    targets.windows = value
                case "wasm":
                    targets.wasm = value
                default:
                    break
                }
            case "dependencies":
                dependencies[key] = parseString(rawValue)
            case "build":
                let value = parseString(rawValue)
                switch key {
                case "optimization":
                    build.optimization = BuildConfig.Optimization(rawValue: value) ?? .debug
                case "hotReload":
                    build.hotReload = parseBool(rawValue)
                case "incrementalBuild":
                    build.incrementalBuild = parseBool(rawValue)
                case "executionMode":
                    build.executionMode = BuildConfig.ExecutionMode(rawValue: value) ?? .hybrid
                default:
                    break
                }
            case "native.ios":
                mutateNativePlatform(\.ios) { platform in
                    switch key {
                    case "minimumVersion":
                        platform.minimumVersion = parseString(rawValue)
                    case "deviceFamily":
                        platform.deviceFamily = parseStringArray(rawValue)
                    case "frameworks":
                        platform.frameworks = parseStringArray(rawValue)
                    case "libs":
                        platform.libs = parseStringArray(rawValue)
                    case "headerSearchPaths":
                        platform.headerSearchPaths = parseStringArray(rawValue)
                    default:
                        break
                    }
                }
            case "native.macos":
                mutateNativePlatform(\.macos) { platform in
                    switch key {
                    case "minimumVersion":
                        platform.minimumVersion = parseString(rawValue)
                    case "frameworks":
                        platform.frameworks = parseStringArray(rawValue)
                    case "libs":
                        platform.libs = parseStringArray(rawValue)
                    case "headerSearchPaths":
                        platform.headerSearchPaths = parseStringArray(rawValue)
                    default:
                        break
                    }
                }
            case "native.ios.pods":
                mutateNativePlatform(\.ios) { platform in
                    platform.pods[key] = parseString(rawValue)
                }
            case "native.macos.pods":
                mutateNativePlatform(\.macos) { platform in
                    platform.pods[key] = parseString(rawValue)
                }
            case "native.ios.ffi":
                let table = parseInlineTable(rawValue)
                mutateNativePlatform(\.ios) { platform in
                    guard let header = table["header"], let lib = table["lib"] else { return }
                    platform.ffi[key] = ApplePlatform.FFIEntry(
                        header: header,
                        lib: lib,
                        bindingsOut: table["bindingsOut"]
                    )
                }
            case "native.macos.ffi":
                let table = parseInlineTable(rawValue)
                mutateNativePlatform(\.macos) { platform in
                    guard let header = table["header"], let lib = table["lib"] else { return }
                    platform.ffi[key] = ApplePlatform.FFIEntry(
                        header: header,
                        lib: lib,
                        bindingsOut: table["bindingsOut"]
                    )
                }
            case "native.ios.signing":
                mutateNativePlatform(\.ios) { platform in
                    var signing = platform.signing ?? ApplePlatform.Signing()
                    switch key {
                    case "teamID":
                        signing.teamID = parseString(rawValue)
                    case "bundleID":
                        signing.bundleID = parseString(rawValue)
                    default:
                        break
                    }
                    platform.signing = signing
                }
            case "native.macos.signing":
                mutateNativePlatform(\.macos) { platform in
                    var signing = platform.signing ?? ApplePlatform.Signing()
                    switch key {
                    case "teamID":
                        signing.teamID = parseString(rawValue)
                    case "bundleID":
                        signing.bundleID = parseString(rawValue)
                    default:
                        break
                    }
                    platform.signing = signing
                }
            default:
                continue
            }
        }

        let resolvedNative: Native? = {
            if native.ios == nil && native.macos == nil {
                return nil
            }
            return native
        }()

        return KiraPackage(
            package: .init(name: pkgName, version: pkgVersion, kira: kiraReq, license: license),
            targets: targets,
            dependencies: dependencies,
            build: build,
            native: resolvedNative
        )
    }

    private func renderToml() -> String {
        func renderArray(_ values: [String]) -> String {
            "[\(values.map { "\"\($0)\"" }.joined(separator: ", "))]"
        }

        func appendPlatform(_ name: String, _ platform: ApplePlatform?, into out: inout [String]) {
            guard let platform else { return }
            out.append("[native.\(name)]")
            if let minimumVersion = platform.minimumVersion {
                out.append("minimumVersion = \"\(minimumVersion)\"")
            }
            if !platform.deviceFamily.isEmpty {
                out.append("deviceFamily = \(renderArray(platform.deviceFamily))")
            }
            out.append("frameworks = \(renderArray(platform.frameworks))")
            out.append("libs = \(renderArray(platform.libs))")
            out.append("headerSearchPaths = \(renderArray(platform.headerSearchPaths))")
            out.append("")

            if !platform.pods.isEmpty {
                out.append("[native.\(name).pods]")
                for (pod, version) in platform.pods.sorted(by: { $0.key < $1.key }) {
                    out.append("\"\(pod)\" = \"\(version)\"")
                }
                out.append("")
            }

            if !platform.ffi.isEmpty {
                out.append("[native.\(name).ffi]")
                for (ffiName, ffi) in platform.ffi.sorted(by: { $0.key < $1.key }) {
                    var table = [
                        "header = \"\(ffi.header)\"",
                        "lib = \"\(ffi.lib)\"",
                    ]
                    if let bindingsOut = ffi.bindingsOut, !bindingsOut.isEmpty {
                        table.append("bindingsOut = \"\(bindingsOut)\"")
                    }
                    out.append("\"\(ffiName)\" = { \(table.joined(separator: ", ")) }")
                }
                out.append("")
            }

            if let signing = platform.signing {
                out.append("[native.\(name).signing]")
                out.append("teamID = \"\(signing.teamID)\"")
                out.append("bundleID = \"\(signing.bundleID)\"")
                out.append("")
            }
        }

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
        for (name, version) in dependencies.sorted(by: { $0.key < $1.key }) {
            out.append("\"\(name)\" = \"\(version)\"")
        }
        out.append("")

        out.append("[build]")
        out.append("optimization = \"\(build.optimization.rawValue)\"")
        out.append("hotReload = \(build.hotReload)")
        out.append("incrementalBuild = \(build.incrementalBuild)")
        out.append("executionMode = \"\(build.executionMode.rawValue)\"")
        out.append("")

        appendPlatform("ios", native?.ios, into: &out)
        appendPlatform("macos", native?.macos, into: &out)

        return out.joined(separator: "\n")
    }
}
