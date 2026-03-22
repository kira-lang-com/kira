import Foundation

public struct SourceText: Sendable {
    public var file: String
    public var text: String

    public init(file: String, text: String) {
        self.file = file
        self.text = text
    }
}

public enum LexerError: Error, CustomStringConvertible, Sendable {
    case illegalKeyword(String, SourceLocation)
    case unexpectedCharacter(Character, SourceLocation)
    case unterminatedString(SourceLocation)
    case unterminatedBlockComment(SourceLocation)

    public var description: String {
        switch self {
        case .illegalKeyword(let kw, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: '\(kw)' is not valid Kira syntax (use 'function')"
        case .unexpectedCharacter(let ch, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: unexpected character '\(ch)'"
        case .unterminatedString(let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: unterminated string literal"
        case .unterminatedBlockComment(let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: unterminated block comment"
        }
    }
}

public struct Lexer {
    public init() {}

    public func lex(_ source: SourceText) throws -> [Token] {
        let scalars = Array(source.text.unicodeScalars)
        var index = 0
        var offset = 0
        var line = 1
        var column = 1

        func location() -> SourceLocation {
            SourceLocation(file: source.file, offset: offset, line: line, column: column)
        }

        func advanceScalar() -> UnicodeScalar? {
            guard index < scalars.count else { return nil }
            let s = scalars[index]
            index += 1
            offset += 1
            if s == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            return s
        }

        func peekScalar(_ n: Int = 0) -> UnicodeScalar? {
            let i = index + n
            guard i < scalars.count else { return nil }
            return scalars[i]
        }

        func makeToken(_ kind: TokenKind, start: SourceLocation, end: SourceLocation) -> Token {
            Token(kind: kind, range: SourceRange(start: start, end: end))
        }

        func isIdentStart(_ s: UnicodeScalar) -> Bool {
            s == "_" || CharacterSet.letters.contains(s)
        }
        func isIdentContinue(_ s: UnicodeScalar) -> Bool {
            isIdentStart(s) || CharacterSet.decimalDigits.contains(s)
        }

        var tokens: [Token] = []

        while let s = peekScalar() {
            let start = location()

            if s == " " || s == "\t" || s == "\r" {
                _ = advanceScalar()
                continue
            }

            if s == "\n" {
                _ = advanceScalar()
                let end = location()
                tokens.append(makeToken(.newline, start: start, end: end))
                continue
            }

            if s == "/" && peekScalar(1) == "/" {
                _ = advanceScalar()
                _ = advanceScalar()
                while let c = peekScalar(), c != "\n" { _ = advanceScalar() }
                continue
            }

            if s == "/" && peekScalar(1) == "*" {
                _ = advanceScalar()
                _ = advanceScalar()
                var depth = 1
                while let c = peekScalar() {
                    if c == "/" && peekScalar(1) == "*" {
                        _ = advanceScalar()
                        _ = advanceScalar()
                        depth += 1
                        continue
                    }
                    if c == "*" && peekScalar(1) == "/" {
                        _ = advanceScalar()
                        _ = advanceScalar()
                        depth -= 1
                        if depth == 0 { break }
                        continue
                    }
                    _ = advanceScalar()
                }
                if depth != 0 {
                    throw LexerError.unterminatedBlockComment(start)
                }
                continue
            }

            if s == "\"" {
                _ = advanceScalar()
                var buffer = ""
                var terminated = false
                while let c = peekScalar() {
                    if c == "\"" {
                        _ = advanceScalar()
                        let end = location()
                        tokens.append(makeToken(.stringLiteral(buffer), start: start, end: end))
                        terminated = true
                        break
                    }
                    if c == "\\" {
                        _ = advanceScalar()
                        guard let esc = advanceScalar() else { throw LexerError.unterminatedString(start) }
                        switch esc {
                        case "n": buffer.append("\n")
                        case "t": buffer.append("\t")
                        case "\"": buffer.append("\"")
                        case "\\": buffer.append("\\")
                        default: buffer.append(Character(esc))
                        }
                        continue
                    }
                    _ = advanceScalar()
                    buffer.append(Character(c))
                }
                if !terminated {
                    throw LexerError.unterminatedString(start)
                }
                continue
            }

            if CharacterSet.decimalDigits.contains(s) {
                var text = ""
                var isFloat = false
                while let c = peekScalar(), CharacterSet.decimalDigits.contains(c) {
                    _ = advanceScalar()
                    text.append(Character(c))
                }
                if peekScalar() == "." && (peekScalar(1).map { CharacterSet.decimalDigits.contains($0) } ?? false) {
                    isFloat = true
                    _ = advanceScalar()
                    text.append(".")
                    while let c = peekScalar(), CharacterSet.decimalDigits.contains(c) {
                        _ = advanceScalar()
                        text.append(Character(c))
                    }
                }
                let end = location()
                if isFloat {
                    tokens.append(makeToken(.floatLiteral(Double(text) ?? 0.0), start: start, end: end))
                } else {
                    tokens.append(makeToken(.intLiteral(Int64(text) ?? 0), start: start, end: end))
                }
                continue
            }

            if isIdentStart(s) {
                var text = ""
                while let c = peekScalar(), isIdentContinue(c) {
                    _ = advanceScalar()
                    text.append(Character(c))
                }
                if text == "func" {
                    throw LexerError.illegalKeyword("func", start)
                }
                let end = location()
                if let kw = Keyword(rawValue: text) {
                    tokens.append(makeToken(.keyword(kw), start: start, end: end))
                } else {
                    tokens.append(makeToken(.identifier(text), start: start, end: end))
                }
                continue
            }

            _ = advanceScalar()
            let end = location()

            switch s {
            case "@": tokens.append(makeToken(.atSign, start: start, end: end))
            case "#": tokens.append(makeToken(.hash, start: start, end: end))
            case "(": tokens.append(makeToken(.lParen, start: start, end: end))
            case ")": tokens.append(makeToken(.rParen, start: start, end: end))
            case "{": tokens.append(makeToken(.lBrace, start: start, end: end))
            case "}": tokens.append(makeToken(.rBrace, start: start, end: end))
            case "[": tokens.append(makeToken(.lBracket, start: start, end: end))
            case "]": tokens.append(makeToken(.rBracket, start: start, end: end))
            case ",": tokens.append(makeToken(.comma, start: start, end: end))
            case ":": tokens.append(makeToken(.colon, start: start, end: end))
            case ";": tokens.append(makeToken(.semicolon, start: start, end: end))
            case ".": tokens.append(makeToken(.dot, start: start, end: end))
            case "=":
                if peekScalar() == "=" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.equalEqual, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.equal, start: start, end: end))
                }
            case "-":
                if peekScalar() == ">" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.arrow, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.minus, start: start, end: end))
                }
            case "+": tokens.append(makeToken(.plus, start: start, end: end))
            case "*": tokens.append(makeToken(.star, start: start, end: end))
            case "/": tokens.append(makeToken(.slash, start: start, end: end))
            case "%": tokens.append(makeToken(.percent, start: start, end: end))
            case "!":
                if peekScalar() == "=" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.bangEqual, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.bang, start: start, end: end))
                }
            case "?": tokens.append(makeToken(.question, start: start, end: end))
            case "&":
                if peekScalar() == "&" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.ampAmp, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.amp, start: start, end: end))
                }
            case "|":
                if peekScalar() == "|" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.pipePipe, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.pipe, start: start, end: end))
                }
            case "^": tokens.append(makeToken(.caret, start: start, end: end))
            case "<":
                if peekScalar() == "=" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.ltEqual, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.lt, start: start, end: end))
                }
            case ">":
                if peekScalar() == "=" {
                    _ = advanceScalar()
                    let end2 = location()
                    tokens.append(makeToken(.gtEqual, start: start, end: end2))
                } else {
                    tokens.append(makeToken(.gt, start: start, end: end))
                }
            default:
                throw LexerError.unexpectedCharacter(Character(s), start)
            }
        }

        let loc = location()
        tokens.append(Token(kind: .eof, range: SourceRange(start: loc, end: loc)))
        return tokens
    }
}
