import Foundation

enum VersionCommand {
    static func run(args: [String]) throws {
        _ = args
        print("kira \(KiraCLIInfo.version)")
    }
}
