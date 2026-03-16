import Foundation

struct CompletionHandler {
    func complete() -> [LSPCompletionItem] {
        [
            .init(label: "function", kind: 14, detail: "keyword"),
            .init(label: "type", kind: 14, detail: "keyword"),
            .init(label: "construct", kind: 14, detail: "keyword"),
            .init(label: "let", kind: 14, detail: "keyword"),
            .init(label: "var", kind: 14, detail: "keyword"),
            .init(label: "return", kind: 14, detail: "keyword"),
        ]
    }
}

