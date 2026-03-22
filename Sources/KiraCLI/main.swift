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
        guard let command = args.first else {
            print(interface())
            return
        }
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
        case "install":
            try InstallCommand.run(args: rest)
        case "help", "-h", "--help":
            print(interface())
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    static func interface() -> String {
        """
        OVERVIEW: Kira command-line tools for projects, builds, docs, packages, and language tooling.

        USAGE: kira <command> [arguments]

        PROJECT COMMANDS:
          new <name>                                         Create a new Kira project.
          build [--target ios|android|macos|linux|windows|wasm] [--release]
                                                             Compile the current project.
          run [path] [--target macos|linux|windows|wasm] [--rebuild]
                                                             Run a Kira file, or launch a cached native macOS app when available. Debug patch sessions start automatically for native debug builds with hotReload enabled.
          watch [--target macos|ios] [--localhost] [--port <number>]
                                                             Start a debug patch server for a native host app without launching it.
          doc [--all|--only-documented] --out <dir> [--force] [--clean]
                                                             Generate API docs.
          package add <name> <version>                       Add a package dependency.
          package remove <name>                              Remove a package dependency.
          package update                                     Rewrite the package manifest.

        TOOLCHAIN COMMANDS:
          install                                            Install the release toolchain to ~/.kira/toolchain/\(KiraCLIInfo.version).
          install --dev                                      Install the current local debug toolchain and refresh ~/.kira/toolchain/current.
          lsp                                                Launch the Kira language server.
          bindgen <header.h> --lib <name> --out <file.kira> Generate Kira FFI bindings from a C header.
          version                                            Print the installed Kira version.

        EXAMPLES:
          kira new HelloKira
          kira build --target windows
          kira doc --out docs --clean
          kira install --dev

        Add ~/.kira/toolchain/current/bin to PATH if you want the installed toolchain available globally.
        """
    }
}

KiraCLI.runMain()
