import Foundation

enum CLIError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case missingArgument(String)
    case invalidOption(String)
    case fileNotFound(String)
    case message(String)

    var description: String {
        switch self {
        case .unknownCommand(let c): return "error: unknown command '\(c)' (try: kira help)"
        case .missingArgument(let a): return "error: missing argument \(a)"
        case .invalidOption(let o): return "error: invalid option \(o)"
        case .fileNotFound(let p): return "error: file not found: \(p)"
        case .message(let m): return "error: \(m)"
        }
    }
}

struct Args {
    var args: [String]
    var i: Int = 0

    init(_ args: [String]) { self.args = args }

    mutating func next() -> String? {
        guard i < args.count else { return nil }
        defer { i += 1 }
        return args[i]
    }

    mutating func peek() -> String? {
        guard i < args.count else { return nil }
        return args[i]
    }

    mutating func consume(_ expected: String) -> Bool {
        guard peek() == expected else { return false }
        _ = next()
        return true
    }
}

