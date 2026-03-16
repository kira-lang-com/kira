import Foundation

struct HoverHandler {
    func hover() -> LSPHover {
        LSPHover(contents: .init(value: "Kira Language Server"))
    }
}

