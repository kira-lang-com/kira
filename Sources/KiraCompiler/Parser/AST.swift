import Foundation

public struct Annotation: Sendable {
    public struct Argument: Sendable {
        public var label: String?
        public var value: Expr

        public init(label: String?, value: Expr) {
            self.label = label
            self.value = value
        }
    }

    public var name: String
    public var arguments: [Argument]
    public var range: SourceRange

    public init(name: String, arguments: [Argument], range: SourceRange) {
        self.name = name
        self.arguments = arguments
        self.range = range
    }
}

public struct TypeRef: Sendable {
    public indirect enum Kind: Sendable {
        case named(String)
        case applied(String, [TypeRef])
        case array(TypeRef)
        case dictionary(key: TypeRef, value: TypeRef)
        case optional(TypeRef)
        case function(params: [TypeRef], returns: TypeRef)
    }

    public var kind: Kind
    public var range: SourceRange

    public init(kind: Kind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}

public struct ModuleAST: Sendable {
    public var imports: [ImportDecl]
    public var declarations: [Decl]
    public var range: SourceRange

    public init(imports: [ImportDecl], declarations: [Decl], range: SourceRange) {
        self.imports = imports
        self.declarations = declarations
        self.range = range
    }
}

public struct ImportDecl: Sendable {
    public var modulePath: String
    public var alias: String?
    public var range: SourceRange

    public init(modulePath: String, alias: String?, range: SourceRange) {
        self.modulePath = modulePath
        self.alias = alias
        self.range = range
    }
}

public enum Decl: Sendable {
    case function(FunctionDecl)
    case externFunction(ExternFunctionDecl)
    case type(TypeDecl)
    case `protocol`(ProtocolDecl)
    case `enum`(EnumDecl)
    case construct(ConstructDecl)
    case constructInstance(ConstructInstanceDecl)
}

public struct Parameter: Sendable {
    public var name: String
    public var type: TypeRef
    public var range: SourceRange

    public init(name: String, type: TypeRef, range: SourceRange) {
        self.name = name
        self.type = type
        self.range = range
    }
}

public struct FunctionDecl: Sendable {
    public var annotations: [Annotation]
    public var isAsync: Bool
    public var name: String
    public var parameters: [Parameter]
    public var returnType: TypeRef?
    public var body: BlockStmt
    public var range: SourceRange

    public init(annotations: [Annotation], isAsync: Bool, name: String, parameters: [Parameter], returnType: TypeRef?, body: BlockStmt, range: SourceRange) {
        self.annotations = annotations
        self.isAsync = isAsync
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
        self.range = range
    }
}

public struct ExternFunctionDecl: Sendable {
    public var annotations: [Annotation]
    public var name: String
    public var parameters: [Parameter]
    public var returnType: TypeRef?
    public var range: SourceRange

    public init(annotations: [Annotation], name: String, parameters: [Parameter], returnType: TypeRef?, range: SourceRange) {
        self.annotations = annotations
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.range = range
    }
}

public struct TypeDecl: Sendable {
    public struct Field: Sendable {
        public var annotations: [Annotation]
        public var isVar: Bool
        public var name: String
        public var type: TypeRef?
        public var initializer: Expr?
        public var range: SourceRange

        public init(annotations: [Annotation], isVar: Bool, name: String, type: TypeRef?, initializer: Expr?, range: SourceRange) {
            self.annotations = annotations
            self.isVar = isVar
            self.name = name
            self.type = type
            self.initializer = initializer
            self.range = range
        }
    }

    public var annotations: [Annotation]
    public var name: String
    public var fields: [Field]
    public var range: SourceRange

    public init(annotations: [Annotation], name: String, fields: [Field], range: SourceRange) {
        self.annotations = annotations
        self.name = name
        self.fields = fields
        self.range = range
    }
}

public struct ProtocolDecl: Sendable {
    public struct Requirement: Sendable {
        public var annotations: [Annotation]
        public var name: String
        public var parameters: [Parameter]
        public var returnType: TypeRef?
        public var range: SourceRange
    }

    public var annotations: [Annotation]
    public var name: String
    public var requirements: [Requirement]
    public var range: SourceRange
}

public struct EnumDecl: Sendable {
    public struct Case: Sendable {
        public struct AssociatedValue: Sendable {
            public var label: String?
            public var type: TypeRef
            public var range: SourceRange
        }
        public var name: String
        public var associatedValues: [AssociatedValue]
        public var range: SourceRange
    }

    public var annotations: [Annotation]
    public var name: String
    public var cases: [Case]
    public var range: SourceRange
}

public struct ConstructDecl: Sendable {
    public struct Modifier: Sendable {
        public var isScoped: Bool
        public var name: String
        public var type: TypeRef?
        public var defaultValue: Expr?
        public var range: SourceRange
    }

    public var name: String
    public var allowedAnnotations: [String]
    public var modifiers: [Modifier]
    public var requiredBlocks: [String]
    public var range: SourceRange
}

public struct ConstructInstanceDecl: Sendable {
    public struct Member: Sendable {
        public enum Kind: Sendable {
            case field(TypeDecl.Field)
            case function(FunctionDecl)
            case block(name: String, body: BlockStmt)
        }
        public var kind: Kind
        public var range: SourceRange
    }

    public var annotations: [Annotation]
    public var constructName: String
    public var name: String
    public var parameters: [Parameter]
    public var members: [Member]
    public var range: SourceRange
}

public struct BlockStmt: Sendable {
    public var statements: [Stmt]
    public var range: SourceRange

    public init(statements: [Stmt], range: SourceRange) {
        self.statements = statements
        self.range = range
    }
}

public enum Stmt: Sendable {
    case variable(VarDeclStmt)
    case `return`(ReturnStmt)
    case expr(Expr)
    case `if`(IfStmt)
}

public struct VarDeclStmt: Sendable {
    public var isVar: Bool
    public var name: String
    public var explicitType: TypeRef?
    public var initializer: Expr
    public var range: SourceRange
}

public struct ReturnStmt: Sendable {
    public var value: Expr?
    public var range: SourceRange
}

public struct IfStmt: Sendable {
    public var condition: Expr
    public var thenBlock: BlockStmt
    public var elseBlock: BlockStmt?
    public var range: SourceRange
}

public indirect enum Expr: Sendable {
    case identifier(String, SourceRange)
    case intLiteral(Int64, SourceRange)
    case floatLiteral(Double, SourceRange)
    case stringLiteral(String, SourceRange)
    case boolLiteral(Bool, SourceRange)
    case nilLiteral(SourceRange)
    case unary(UnaryExpr)
    case binary(BinaryExpr)
    case call(CallExpr)
    case member(MemberExpr)
    case assign(AssignExpr)
    case shaderMacro(ShaderMacroExpr)

    public var range: SourceRange {
        switch self {
        case .identifier(_, let r): return r
        case .intLiteral(_, let r): return r
        case .floatLiteral(_, let r): return r
        case .stringLiteral(_, let r): return r
        case .boolLiteral(_, let r): return r
        case .nilLiteral(let r): return r
        case .unary(let u): return u.range
        case .binary(let b): return b.range
        case .call(let c): return c.range
        case .member(let m): return m.range
        case .assign(let a): return a.range
        case .shaderMacro(let s): return s.range
        }
    }
}

public struct UnaryExpr: Sendable {
    public var op: UnaryOp
    public var expr: Expr
    public var range: SourceRange
    public init(op: UnaryOp, expr: Expr, range: SourceRange) {
        self.op = op
        self.expr = expr
        self.range = range
    }
}

public struct BinaryExpr: Sendable {
    public var op: BinaryOp
    public var lhs: Expr
    public var rhs: Expr
    public var range: SourceRange
    public init(op: BinaryOp, lhs: Expr, rhs: Expr, range: SourceRange) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
        self.range = range
    }
}

public struct CallExpr: Sendable {
    public var callee: Expr
    public var arguments: [CallArgument]
    public var trailingBlock: BlockStmt?
    public var range: SourceRange
    public init(callee: Expr, arguments: [CallArgument], trailingBlock: BlockStmt?, range: SourceRange) {
        self.callee = callee
        self.arguments = arguments
        self.trailingBlock = trailingBlock
        self.range = range
    }
}

public struct MemberExpr: Sendable {
    public var base: Expr
    public var name: String
    public var range: SourceRange
    public init(base: Expr, name: String, range: SourceRange) {
        self.base = base
        self.name = name
        self.range = range
    }
}

public struct AssignExpr: Sendable {
    public var target: Expr
    public var value: Expr
    public var range: SourceRange
    public init(target: Expr, value: Expr, range: SourceRange) {
        self.target = target
        self.value = value
        self.range = range
    }
}

public struct ShaderMacroExpr: Sendable {
    public var functionName: String
    public var range: SourceRange
    public init(functionName: String, range: SourceRange) {
        self.functionName = functionName
        self.range = range
    }
}

public struct CallArgument: Sendable {
    public var label: String?
    public var value: Expr
    public var range: SourceRange
}

public enum UnaryOp: Sendable { case negate, not }

public enum BinaryOp: Sendable {
    case add, sub, mul, div, mod
    case eq, neq, lt, gt, lte, gte
    case and, or
}
