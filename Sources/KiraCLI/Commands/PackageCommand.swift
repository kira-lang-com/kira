import Foundation

enum PackageCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        guard let sub = a.next() else { throw CLIError.missingArgument("<add|remove|update>") }
        switch sub {
        case "add":
            guard let name = a.next(), let version = a.next() else { throw CLIError.missingArgument("add <name> <version>") }
            try mutate { pkg in pkg.dependencies[name] = version }
        case "remove":
            guard let name = a.next() else { throw CLIError.missingArgument("remove <name>") }
            try mutate { pkg in pkg.dependencies.removeValue(forKey: name) }
        case "update":
            try mutate { _ in }
        default:
            throw CLIError.invalidOption(sub)
        }
    }

    private static func mutate(_ f: (inout KiraPackage) -> Void) throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let url = cwd.appendingPathComponent("Kira.toml")
        var pkg = try KiraPackage.load(from: url)
        f(&pkg)
        try pkg.save(to: url)
    }
}
