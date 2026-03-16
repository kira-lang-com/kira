import Foundation

public enum Keyword: String, CaseIterable, Sendable {
    case `let`
    case `var`
    case `type`
    case `function`
    case `construct`
    case `protocol`
    case `enum`
    case `match`
    case `case`
    case `return`
    case `import`
    case `as`
    case `extern`
    case `async`
    case `await`
    case `if`
    case `else`
    case `for`
    case `in`
    case `switch`
}

public enum TokenKind: Hashable, Sendable {
    case eof
    case identifier(String)
    case intLiteral(Int64)
    case floatLiteral(Double)
    case stringLiteral(String)

    case keyword(Keyword)

    case atSign
    case hash

    case lParen, rParen
    case lBrace, rBrace
    case lBracket, rBracket
    case comma
    case colon
    case semicolon
    case dot
    case equal
    case equalEqual
    case bangEqual
    case ltEqual
    case gtEqual
    case ampAmp
    case pipePipe
    case arrow

    case plus, minus, star, slash, percent
    case bang
    case question
    case amp, pipe, caret
    case lt, gt

    case newline
}

public struct Token: Hashable, Sendable {
    public var kind: TokenKind
    public var range: SourceRange

    public init(kind: TokenKind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}
