import Foundation

public struct DocRenderer: Sendable {
    public init() {}

    public func render(symbol: DocSymbol) -> String {
        var out: [String] = []
        out.append("# \(symbol.name)")
        out.append("")
        out.append("**Kind:** \(symbol.kind.rawValue.capitalized)")
        out.append("**Module:** \(symbol.moduleName)")
        out.append("")
        if let doc = symbol.doc, !doc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(doc)
            out.append("")
        }
        if !symbol.properties.isEmpty {
            out.append("## Properties")
            out.append("")
            out.append("<!-- kira:generated:start -->")
            for p in symbol.properties {
                out.append("### \(p.name)")
                out.append("`\((p.signature).trimmingCharacters(in: .whitespaces))`")
                if let d = p.doc, !d.isEmpty {
                    out.append(d)
                }
                out.append("")
            }
            if out.last == "" { _ = out.popLast() }
            out.append("<!-- kira:generated:end -->")
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    public func writeFenceSafe(rendered: String, to url: URL, force: Bool) throws {
        if force || !FileManager.default.fileExists(atPath: url.path) {
            try ensureDirectory(url)
            try rendered.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let existing = try String(contentsOf: url, encoding: .utf8)
        guard let startRange = existing.range(of: "<!-- kira:generated:start -->"),
              let endRange = existing.range(of: "<!-- kira:generated:end -->") else {
            // Fence deleted: treat as fully manual forever.
            return
        }

        guard let newStart = rendered.range(of: "<!-- kira:generated:start -->"),
              let newEnd = rendered.range(of: "<!-- kira:generated:end -->") else {
            return
        }

        let head = existing[..<startRange.lowerBound]
        let tail = existing[endRange.upperBound...]
        let middle = rendered[newStart.lowerBound..<newEnd.upperBound]
        let merged = String(head) + String(middle) + String(tail)
        try merged.write(to: url, atomically: true, encoding: .utf8)
    }

    private func ensureDirectory(_ url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

