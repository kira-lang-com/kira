import Foundation

enum NewCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        guard let name = a.next() else { throw CLIError.missingArgument("<name>") }
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)

        let manifest = KiraPackage(
            package: .init(name: name, version: "0.1.0", kira: ">=1.0.0", license: "Apache-2.0"),
            targets: .init(),
            dependencies: ["Kira.Graphics": "0.1.0"],
            build: BuildConfig()
        )
        try manifest.save(to: root.appendingPathComponent("Kira.toml"))

        let main = """
        import Kira.Graphics

        @main
        function main() {
            let x: Float = 12
            let y = 12.0
            let z = x + y
            print(z)
            return
        }
        """
        try main.write(to: root.appendingPathComponent("Sources/main.kira"), atomically: true, encoding: .utf8)
        print("Created \(name)")
    }
}
