import Foundation

public struct DocSymbol: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case widget, construct, type, `enum`, `protocol`, function }

    public struct Property: Hashable, Sendable {
        public var name: String
        public var signature: String
        public var doc: String?
    }

    public var kind: Kind
    public var moduleName: String
    public var name: String
    public var doc: String?
    public var properties: [Property]
}

public struct DocExtractor: Sendable {
    public init() {}

    public func extract(from typed: TypedModule, moduleName: String) -> [DocSymbol] {
        var symbols: [DocSymbol] = []

        func docString(from annotations: [Annotation]) -> String? {
            guard let doc = annotations.first(where: { $0.name == "Doc" }) else { return nil }
            guard let first = doc.arguments.first?.value else { return nil }
            if case .stringLiteral(let s, _) = first { return s }
            return nil
        }

        for decl in typed.ast.declarations {
            switch decl {
            case .construct(let c):
                symbols.append(DocSymbol(kind: .construct, moduleName: moduleName, name: c.name, doc: nil, properties: []))
            case .typealias:
                // Typealiases are implementation details and not part of the public docs for now.
                break
            case .type(let t):
                let props = t.fields.map { f in
                    let sig = f.type.map { typeSystemString($0) } ?? "<inferred>"
                    return DocSymbol.Property(name: f.name, signature: sig, doc: docString(from: f.annotations))
                }
                symbols.append(DocSymbol(kind: .type, moduleName: moduleName, name: t.name, doc: docString(from: t.annotations), properties: props))
            case .enum(let e):
                symbols.append(DocSymbol(kind: .enum, moduleName: moduleName, name: e.name, doc: docString(from: e.annotations), properties: []))
            case .protocol(let p):
                symbols.append(DocSymbol(kind: .protocol, moduleName: moduleName, name: p.name, doc: docString(from: p.annotations), properties: []))
            case .function(let f):
                symbols.append(DocSymbol(kind: .function, moduleName: moduleName, name: f.name, doc: docString(from: f.annotations), properties: []))
            case .externFunction(let f):
                symbols.append(DocSymbol(kind: .function, moduleName: moduleName, name: f.name, doc: docString(from: f.annotations), properties: []))
            case .constructInstance(let ci):
                let fields = ci.members.compactMap { m -> TypeDecl.Field? in
                    if case .field(let f) = m.kind { return f }
                    return nil
                }
                let props = fields.map { f in
                    let sig = f.type.map { typeSystemString($0) } ?? "<inferred>"
                    let annPrefix = f.annotations.map { "@\($0.name)" }.joined(separator: " ")
                    let fullSig = annPrefix.isEmpty ? sig : "\(annPrefix) \(sig)"
                    return DocSymbol.Property(name: f.name, signature: fullSig, doc: docString(from: f.annotations))
                }
                let kind: DocSymbol.Kind = (ci.constructName == "Widget") ? .widget : .type
                symbols.append(DocSymbol(kind: kind, moduleName: moduleName, name: ci.name, doc: docString(from: ci.annotations), properties: props))
            case .globalVar:
                // Global vars are runtime storage, not part of the public API docs for now.
                break
            }
        }

        return symbols
    }

    private func typeSystemString(_ ref: TypeRef) -> String {
        switch ref.kind {
        case .named(let n): return n
        case .applied(let b, let args):
            return "\(b)<\(args.map(typeSystemString).joined(separator: ", "))>"
        case .fixedArray(let element, let count):
            return "CArray<\(typeSystemString(element)), \(count)>"
        case .array(let inner): return "[\(typeSystemString(inner))]"
        case .dictionary(let k, let v): return "[\(typeSystemString(k)): \(typeSystemString(v))]"
        case .optional(let inner): return "\(typeSystemString(inner))?"
        case .function(let ps, let r):
            return "(\(ps.map(typeSystemString).joined(separator: ", "))) -> \(typeSystemString(r))"
        }
    }
}
