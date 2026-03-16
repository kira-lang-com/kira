import Foundation

public struct LSPInitializeParams: Codable, Sendable {
    public var processId: Int?
    public var rootUri: String?
    public var capabilities: [String: JSONValue]?
}

public struct LSPServerCapabilities: Codable, Sendable {
    public var textDocumentSync: Int = 1
    public var completionProvider: CompletionOptions? = CompletionOptions()
    public var hoverProvider: Bool = true
    public var definitionProvider: Bool = true
    public var renameProvider: Bool = true
    public var documentFormattingProvider: Bool = true
    public var inlayHintProvider: Bool = true

    public struct CompletionOptions: Codable, Sendable {
        public var resolveProvider: Bool = false
        public var triggerCharacters: [String] = ["."]
    }
}

public struct LSPInitializeResult: Codable, Sendable {
    public var capabilities: LSPServerCapabilities
}

public struct LSPCompletionItem: Codable, Sendable {
    public var label: String
    public var kind: Int? // 2 = method, 6 = variable, 14 = keyword
    public var detail: String?
}

public struct LSPHover: Codable, Sendable {
    public struct Contents: Codable, Sendable {
        public var kind: String = "markdown"
        public var value: String
    }
    public var contents: Contents
}

// Minimal JSON value for passing through unknown fields.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

