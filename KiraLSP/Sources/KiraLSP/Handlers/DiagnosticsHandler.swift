import Foundation
import KiraCompiler

struct DiagnosticsHandler {
    func diagnostics(for text: String, uri: String) -> [JSONValue] {
        // Scaffold: run the compiler and report the first error if any.
        do {
            _ = try CompilerDriver().compile(source: SourceText(file: uri, text: text), target: .macOS(arch: .arm64))
            return []
        } catch {
            let msg = String(describing: error)
            return [
                .object([
                    "range": .object([
                        "start": .object(["line": .number(0), "character": .number(0)]),
                        "end": .object(["line": .number(0), "character": .number(1)]),
                    ]),
                    "severity": .number(1),
                    "source": .string("kira"),
                    "message": .string(msg),
                ])
            ]
        }
    }
}

