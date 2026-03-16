import Foundation

public struct SourceLocation: Hashable, Sendable {
    public var file: String
    public var offset: Int
    public var line: Int
    public var column: Int

    public init(file: String, offset: Int, line: Int, column: Int) {
        self.file = file
        self.offset = offset
        self.line = line
        self.column = column
    }
}

public struct SourceRange: Hashable, Sendable {
    public var start: SourceLocation
    public var end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }
}

