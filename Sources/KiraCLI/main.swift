import Foundation

enum KiraCLI {
    static func runMain() {
        do {
            try dispatch(args: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }

    static func dispatch(args: [String]) throws {
        let command = args.first ?? "version"
        let rest = Array(args.dropFirst())

        switch command {
        case "version":
            try VersionCommand.run(args: rest)
        case "new":
            try NewCommand.run(args: rest)
        case "build":
            try BuildCommand.run(args: rest)
        case "run":
            try RunCommand.run(args: rest)
        case "watch":
            try WatchCommand.run(args: rest)
        case "bindgen":
            try BindgenCommand.run(args: rest)
        case "doc":
            try DocCommand.run(args: rest)
        case "package":
            try PackageCommand.run(args: rest)
        case "lsp":
            try LSPCommand.run(args: rest)
        case "help", "-h", "--help":
            print(usage())
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    static func usage() -> String {
        """
        kira <command> [args]

        Commands:
          new <name>
          build [--target ios|android|macos|linux|windows|wasm] [--release]
          run
          watch
          bindgen <header.h> --lib <name> --out <file.kira>
          doc [--all|--only-documented] --out <dir> [--force] [--clean]
          package add <name> <version>
          package remove <name>
          package update
          lsp
          version
        """
    }
}

KiraCLI.runMain()
