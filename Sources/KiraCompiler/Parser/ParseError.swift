import Foundation

public enum ParseError: Error, CustomStringConvertible, Sendable {
    case unexpectedToken(expected: String, got: TokenKind, at: SourceLocation)
    case message(String, SourceLocation)

    public var description: String {
        switch self {
        case .unexpectedToken(let expected, let got, let at):
            return "\(at.file):\(at.line):\(at.column): error: expected \(expected), got \(got)"
        case .message(let msg, let at):
            return "\(at.file):\(at.line):\(at.column): error: \(msg)"
        }
    }
}
