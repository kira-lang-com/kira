import Foundation

@main
public struct LSPServerMain {
    public static func main() {
        let transport = JSONRPCTransport()
        let completion = CompletionHandler()
        let hover = HoverHandler()

        // Extremely small server loop: consumes one JSON object per stdin read.
        while let data = transport.readLineMessage() {
            guard let msg = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) else { continue }
            guard let method = msg.method else { continue }

            switch method {
            case "initialize":
                let result = JSONRPCMessage(
                    jsonrpc: "2.0",
                    id: msg.id,
                    method: nil,
                    params: nil,
                    result: .object([
                        "capabilities": .object(try! toJSONValue(LSPServerCapabilities()))
                    ]),
                    error: nil
                )
                transport.send(result)
            case "textDocument/completion":
                let items = completion.complete()
                let result = JSONRPCMessage(
                    jsonrpc: "2.0",
                    id: msg.id,
                    method: nil,
                    params: nil,
                    result: .array((try? items.map { .object(try toJSONValue($0)) }) ?? []),
                    error: nil
                )
                transport.send(result)
            case "textDocument/hover":
                let h = hover.hover()
                let result = JSONRPCMessage(
                    jsonrpc: "2.0",
                    id: msg.id,
                    method: nil,
                    params: nil,
                    result: .object(try! toJSONValue(h)),
                    error: nil
                )
                transport.send(result)
            default:
                // Respond with empty result to keep clients happy.
                transport.send(JSONRPCMessage(jsonrpc: "2.0", id: msg.id, method: nil, params: nil, result: .null, error: nil))
            }
        }
    }

    private static func toJSONValue<T: Encodable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return obj
    }
}

