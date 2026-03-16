import Foundation

public struct StateSerializer: Sendable {
    public init() {}

    public func serialize<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public func deserialize<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

