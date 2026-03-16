import Foundation

public struct JSONRPCMessage: Codable, Sendable {
    public var jsonrpc: String?
    public var id: JSONValue?
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: JSONValue?
}

public final class JSONRPCTransport: @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.input = input
        self.output = output
    }

    public func readLineMessage() -> Data? {
        // Accept newline-delimited JSON for smoke tests / simple clients.
        let data = input.availableData
        if data.isEmpty { return nil }
        return data
    }

    public func send(_ message: JSONRPCMessage) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(message) else { return }
        output.write(data)
        output.write(Data([0x0A]))
    }
}

