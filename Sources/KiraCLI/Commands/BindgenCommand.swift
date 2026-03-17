import Foundation
import KiraCompiler

enum BindgenCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        guard let headerPath = a.next() else { throw CLIError.missingArgument("<header.h>") }
        var lib: String?
        var out: String?
        while let tok = a.next() {
            switch tok {
            case "--lib":
                lib = a.next()
            case "--out":
                out = a.next()
            case "--help", "-h":
                print("kira bindgen <header.h> --lib <name> --out <file.kira>")
                return
            default:
                throw CLIError.invalidOption(tok)
            }
        }
        guard let lib, let out else { throw CLIError.missingArgument("--lib/--out") }
        let kira = BindgenEngine().generate(headerPath: headerPath, libraryName: lib, platform: .current)
        try kira.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
    }
}
