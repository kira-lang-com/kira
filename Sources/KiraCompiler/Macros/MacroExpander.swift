import Foundation

public struct MacroExpander: Sendable {
    public init() {}

    /// Validates and records macro uses. The current scaffold leaves the macro expression intact;
    /// IR lowering embeds a stable string payload.
    public func validate(module: ModuleAST) throws {
        let functions: [String: FunctionDecl] = Dictionary(
            uniqueKeysWithValues: module.declarations.compactMap { decl -> (String, FunctionDecl)? in
                if case .function(let fn) = decl { return (fn.name, fn) }
                return nil
            }
        )

        func stage(from annotations: [Annotation]) -> ShaderMacro.Stage? {
            if annotations.contains(where: { $0.name == "VertexShader" }) { return .vertex }
            if annotations.contains(where: { $0.name == "FragmentShader" }) { return .fragment }
            if annotations.contains(where: { $0.name == "ComputeShader" }) { return .compute }
            if annotations.contains(where: { $0.name == "RayGenerationShader" }) { return .rayGeneration }
            if annotations.contains(where: { $0.name == "ClosestHitShader" }) { return .closestHit }
            if annotations.contains(where: { $0.name == "AnyHitShader" }) { return .anyHit }
            if annotations.contains(where: { $0.name == "MissShader" }) { return .miss }
            if annotations.contains(where: { $0.name == "TaskShader" }) { return .task }
            if annotations.contains(where: { $0.name == "MeshShader" }) { return .mesh }
            return nil
        }

        func walkExpr(_ e: Expr) throws {
            switch e {
            case .shaderMacro(let sm):
                let functionName = sm.functionName
                let r = sm.range
                guard let fn = functions[functionName] else {
                    throw SemanticError.unknownIdentifier(functionName, r.start)
                }
                guard stage(from: fn.annotations) != nil else {
                    throw SemanticError.typeMismatch(expected: .named("ShaderFunction"), got: .named("Function"), r.start, hint: "add a shader stage annotation (e.g. @VertexShader)")
                }
            case .unary(let u):
                try walkExpr(u.expr)
            case .binary(let b):
                try walkExpr(b.lhs)
                try walkExpr(b.rhs)
            case .call(let c):
                try walkExpr(c.callee)
                for a in c.arguments { try walkExpr(a.value) }
                if let trailing = c.trailingBlock {
                    for st in trailing.statements { try walkStmt(st) }
                }
            case .member(let m):
                try walkExpr(m.base)
            case .index(let i):
                try walkExpr(i.base)
                try walkExpr(i.index)
            case .assign(let a):
                try walkExpr(a.target)
                try walkExpr(a.value)
            default:
                break
            }
        }

        func walkStmt(_ s: Stmt) throws {
            switch s {
            case .variable(let vd):
                try walkExpr(vd.initializer)
            case .return(let rs):
                if let v = rs.value { try walkExpr(v) }
            case .expr(let e):
                try walkExpr(e)
            case .if(let ifs):
                try walkExpr(ifs.condition)
                for st in ifs.thenBlock.statements { try walkStmt(st) }
                if let eb = ifs.elseBlock {
                    for st in eb.statements { try walkStmt(st) }
                }
            case .while(let whileStmt):
                try walkExpr(whileStmt.condition)
                for st in whileStmt.body.statements { try walkStmt(st) }
            case .match(let matchStmt):
                try walkExpr(matchStmt.value)
                for matchCase in matchStmt.cases {
                    for statement in matchCase.body.statements {
                        try walkStmt(statement)
                    }
                }
            }
        }

        for decl in module.declarations {
            if case .function(let fn) = decl {
                for st in fn.body.statements { try walkStmt(st) }
            }
        }
    }
}
