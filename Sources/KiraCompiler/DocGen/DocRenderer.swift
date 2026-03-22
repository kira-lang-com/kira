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
        appendSection(title: "Properties", fence: nil, members: symbol.properties, into: &out)
        appendSection(title: "Methods", fence: "methods", members: symbol.methods, into: &out)
        appendSection(title: "Variants", fence: "variants", members: symbol.variants, into: &out)
        appendSection(title: "Requirements", fence: "requirements", members: symbol.requirements, into: &out)
        return out.joined(separator: "\n")
    }

    public func writeFenceSafe(rendered: String, to url: URL, force: Bool) throws {
        if force || !FileManager.default.fileExists(atPath: url.path) {
            try ensureDirectory(url)
            try rendered.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let existing = try String(contentsOf: url, encoding: .utf8)
        let keys = fenceKeys(in: rendered)
        guard !keys.isEmpty else {
            return
        }

        var merged = existing
        for key in keys.reversed() {
            guard let existingFence = fenceRange(for: key, in: merged),
                  let renderedFence = fenceRange(for: key, in: rendered) else {
                return
            }
            merged.replaceSubrange(existingFence.range, with: rendered[renderedFence.range])
        }
        try merged.write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendSection(title: String, fence: String?, members: [DocSymbol.Member], into out: inout [String]) {
        guard !members.isEmpty else { return }
        out.append("## \(title)")
        out.append("")
        out.append(fenceStartMarker(fence))
        for member in members {
            out.append("### \(member.name)")
            out.append("`\((member.signature).trimmingCharacters(in: .whitespaces))`")
            if let doc = member.doc, !doc.isEmpty {
                out.append(doc)
            }
            out.append("")
        }
        if out.last == "" { _ = out.popLast() }
        out.append(fenceEndMarker(fence))
        out.append("")
    }

    private func fenceStartMarker(_ fence: String?) -> String {
        guard let fence else { return "<!-- kira:generated:start -->" }
        return "<!-- kira:generated:\(fence):start -->"
    }

    private func fenceEndMarker(_ fence: String?) -> String {
        guard let fence else { return "<!-- kira:generated:end -->" }
        return "<!-- kira:generated:\(fence):end -->"
    }

    private func fenceKeys(in text: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"<!-- kira:generated(?::([a-z]+))?:start -->"#)
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex?.matches(in: text, range: nsRange).compactMap { match in
            if let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
            return ""
        } ?? []
    }

    private func fenceRange(for key: String, in text: String) -> (range: Range<String.Index>, inner: Range<String.Index>)? {
        let start = key.isEmpty ? "<!-- kira:generated:start -->" : "<!-- kira:generated:\(key):start -->"
        let end = key.isEmpty ? "<!-- kira:generated:end -->" : "<!-- kira:generated:\(key):end -->"
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        return (startRange.lowerBound..<endRange.upperBound, startRange.upperBound..<endRange.lowerBound)
    }

    private func ensureDirectory(_ url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
