import Foundation

public struct DocSymbol: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case widget, construct, type, `enum`, `protocol`, function }

    public struct Member: Hashable, Sendable {
        public var name: String
        public var signature: String
        public var doc: String?
    }

    public var kind: Kind
    public var moduleName: String
    public var name: String
    public var doc: String?
    public var properties: [Member]
    public var methods: [Member]
    public var variants: [Member]
    public var requirements: [Member]
}

public struct DocExtractor: Sendable {
    public init() {}

    public func extract(from typed: TypedModule, moduleName: String, sourceRoot: String? = nil) -> [DocSymbol] {
        var symbols: [DocSymbol] = []
        let normalizedRoot = sourceRoot.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        }

        func docString(from annotations: [Annotation]) -> String? {
            guard let doc = annotations.first(where: { $0.name == "Doc" }) else { return nil }
            guard let first = doc.arguments.first?.value else { return nil }
            if case .stringLiteral(let s, _) = first { return s }
            return nil
        }

        for decl in typed.ast.declarations {
            if let normalizedRoot {
                let declPath = URL(fileURLWithPath: decl.range.start.file).standardizedFileURL.path
                if !declPath.hasPrefix(normalizedRoot + "/") && declPath != normalizedRoot {
                    continue
                }
            }
            switch decl {
            case .construct(let c):
                symbols.append(DocSymbol(kind: .construct, moduleName: moduleName, name: c.name, doc: nil, properties: [], methods: [], variants: [], requirements: []))
            case .typealias:
                // Typealiases are implementation details and not part of the public docs for now.
                break
            case .type(let t):
                let props = t.fields.map { f in
                    let sig = f.type.map { typeSystemString($0) } ?? "<inferred>"
                    return DocSymbol.Member(name: f.name, signature: sig, doc: docString(from: f.annotations))
                }
                let methods = t.methods.map { methodMember($0, prefix: "function") }
                    + t.statics.map { methodMember($0, prefix: "static function") }
                symbols.append(DocSymbol(kind: .type, moduleName: moduleName, name: t.name, doc: docString(from: t.annotations), properties: props, methods: methods, variants: [], requirements: []))
            case .enum(let e):
                let variants = e.cases.map { enumCase in
                    DocSymbol.Member(
                        name: enumCase.name,
                        signature: enumCaseSignature(enumCase),
                        doc: docString(from: enumCase.annotations)
                    )
                }
                symbols.append(DocSymbol(kind: .enum, moduleName: moduleName, name: e.name, doc: docString(from: e.annotations), properties: [], methods: [], variants: variants, requirements: []))
            case .protocol(let p):
                let requirements = p.requirements.map {
                    DocSymbol.Member(
                        name: $0.name,
                        signature: functionSignature(name: $0.name, parameters: $0.parameters, returnType: $0.returnType, prefix: "function"),
                        doc: docString(from: $0.annotations)
                    )
                }
                symbols.append(DocSymbol(kind: .protocol, moduleName: moduleName, name: p.name, doc: docString(from: p.annotations), properties: [], methods: [], variants: [], requirements: requirements))
            case .function(let f):
                symbols.append(DocSymbol(kind: .function, moduleName: moduleName, name: f.name, doc: docString(from: f.annotations), properties: [], methods: [], variants: [], requirements: []))
            case .externFunction(let f):
                symbols.append(DocSymbol(kind: .function, moduleName: moduleName, name: f.name, doc: docString(from: f.annotations), properties: [], methods: [], variants: [], requirements: []))
            case .constructInstance(let ci):
                let fields = ci.members.compactMap { m -> TypeDecl.Field? in
                    if case .field(let f) = m.kind { return f }
                    return nil
                }
                let props = fields.map { f in
                    let sig = f.type.map { typeSystemString($0) } ?? "<inferred>"
                    let annPrefix = f.annotations.map { "@\($0.name)" }.joined(separator: " ")
                    let fullSig = annPrefix.isEmpty ? sig : "\(annPrefix) \(sig)"
                    return DocSymbol.Member(name: f.name, signature: fullSig, doc: docString(from: f.annotations))
                }
                let kind: DocSymbol.Kind = (ci.constructName == "Widget") ? .widget : .type
                symbols.append(DocSymbol(kind: kind, moduleName: moduleName, name: ci.name, doc: docString(from: ci.annotations), properties: props, methods: [], variants: [], requirements: []))
            case .globalVar:
                // Global vars are runtime storage, not part of the public API docs for now.
                break
            }
        }

        return symbols
    }

    private func methodMember(_ fn: FunctionDecl, prefix: String) -> DocSymbol.Member {
        DocSymbol.Member(
            name: fn.name,
            signature: functionSignature(name: fn.name, parameters: fn.parameters, returnType: fn.returnType, prefix: prefix),
            doc: docString(from: fn.annotations)
        )
    }

    private func functionSignature(name: String, parameters: [Parameter], returnType: TypeRef?, prefix: String) -> String {
        let params = parameters.map { "\($0.name): \(typeSystemString($0.type))" }.joined(separator: ", ")
        let returnSuffix = returnType.map { " -> \(typeSystemString($0))" } ?? ""
        return "\(prefix) \(name)(\(params))\(returnSuffix)"
    }

    private func enumCaseSignature(_ enumCase: EnumDecl.Case) -> String {
        guard !enumCase.associatedValues.isEmpty else { return enumCase.name }
        let values = enumCase.associatedValues.map { associatedValue in
            let label = associatedValue.label.map { "\($0): " } ?? ""
            return "\(label)\(typeSystemString(associatedValue.type))"
        }.joined(separator: ", ")
        return "\(enumCase.name)(\(values))"
    }

    private func docString(from annotations: [Annotation]) -> String? {
        guard let doc = annotations.first(where: { $0.name == "Doc" }) else { return nil }
        guard let first = doc.arguments.first?.value else { return nil }
        if case .stringLiteral(let s, _) = first { return s }
        return nil
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
