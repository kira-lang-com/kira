import Foundation
#if canImport(Clibclang)
import Clibclang
#endif

public indirect enum CKiraFFIType: Sendable {
    case void
    case bool
    case int8, int16, int32, int64
    case uint8, uint16, uint32, uint64
    case float32, float64
    case pointer(CKiraFFIType)       // e.g. int32* → .pointer(.int32)
    case constPointer(CKiraFFIType)  // const T*
    case opaquePointer               // void* or unknown pointer
    case named(String)               // typedef name not resolved to primitive
    case functionPointer             // function pointer — emitted as CPointer<CVoid>
}

public struct ParsedCFunction: Sendable {
    public let name: String
    public let returnType: CKiraFFIType
    public let parameters: [(name: String?, type: CKiraFFIType)]
}

public struct ParsedCStruct: Sendable {
    public let name: String
    public let fields: [(name: String, type: CKiraFFIType)]
}

public struct ParsedCEnum: Sendable {
    public let name: String
    public let cases: [(name: String, value: Int64)]
}

public struct ParsedCTypedef: Sendable {
    public let alias: String
    public let underlying: CKiraFFIType
}

public struct ParsedHeader: Sendable {
    public var functions: [ParsedCFunction] = []
    public var structs: [ParsedCStruct] = []
    public var enums: [ParsedCEnum] = []
    public var typedefs: [ParsedCTypedef] = []
}

public enum BindgenPlatform: Sendable {
    case iOS
    case android
    case macOS
    case linux
    case windows
    case current

    var resolved: BindgenPlatform {
        switch self {
        case .current:
            #if os(iOS)
            return .iOS
            #elseif os(macOS)
            return .macOS
            #elseif os(Windows)
            return .windows
            #elseif os(Linux)
            return .linux
            #elseif os(Android)
            return .android
            #else
            return .linux
            #endif
        default:
            return self
        }
    }

    var ffiLinkage: String {
        switch resolved {
        case .iOS: return ", linkage: .static"
        default: return ""
        }
    }

    var nameForComment: String {
        switch resolved {
        case .iOS: return "iOS"
        case .android: return "android"
        case .macOS: return "macOS"
        case .linux: return "linux"
        case .windows: return "windows"
        case .current: return "current"
        }
    }
}

public struct BindgenEngine: Sendable {
    public init() {}

    #if canImport(Clibclang)
    public func generate(
        headerPath: String,
        libraryName: String,
        platform: BindgenPlatform = .current
    ) -> String {
        let index = clang_createIndex(0, 0)
        defer { clang_disposeIndex(index) }

        var clangArgs: [String] = [
            "-x", "c",
            "-std=c11",
        ]

        let headerDir = (headerPath as NSString).deletingLastPathComponent
        if !headerDir.isEmpty {
            clangArgs += ["-I", headerDir]
        }

        #if os(macOS) || os(iOS)
        if let sdkPath = getSDKPath() {
            clangArgs += ["-isysroot", sdkPath]
        }
        #endif

        let duplicatedArgs: [UnsafeMutablePointer<CChar>?] = clangArgs.map { strdup($0) }
        defer { duplicatedArgs.forEach { if let p = $0 { free(p) } } }
        let cArgs: [UnsafePointer<CChar>?] = duplicatedArgs.map { $0.map { UnsafePointer($0) } }

        let tu: CXTranslationUnit? = cArgs.withUnsafeBufferPointer { argsBuf in
            headerPath.withCString { pathPtr in
                clang_parseTranslationUnit(
                    index,
                    pathPtr,
                    argsBuf.baseAddress,
                    Int32(argsBuf.count),
                    nil,
                    0,
                    UInt32(CXTranslationUnit_SkipFunctionBodies.rawValue)
                )
            }
        }

        guard let tu else { return "// error: failed to parse header \(headerPath)" }
        defer { clang_disposeTranslationUnit(tu) }

        let visitor = HeaderVisitor()
        visitor.walk(translationUnit: tu)
        return emitKira(parsed: visitor.parsed, libraryName: libraryName, platform: platform.resolved)
    }
    #else
    public func generate(
        headerPath: String,
        libraryName: String,
        platform: BindgenPlatform = .current
    ) -> String {
        _ = headerPath
        _ = libraryName
        _ = platform
        return "// error: libclang is not available. Install llvm: brew install llvm"
    }
    #endif

    // Backwards-compatible entrypoint used by `kira bindgen` and existing tests.
    public func generate(headerText: String, libraryName: String) -> String {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kira-bindgen-\(UUID().uuidString).h")
        do {
            try headerText.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            return "// error: failed to create temporary header for bindgen"
        }
        return generate(headerPath: tmpURL.path, libraryName: libraryName, platform: .current)
    }
}

#if canImport(Clibclang)

private final class HeaderVisitor {
    var parsed = ParsedHeader()

    private var seenFunctions: Set<String> = []
    private var structIndexByName: [String: Int] = [:]
    private var enumIndexByName: [String: Int] = [:]
    private var seenTypedefs: Set<String> = []

    func walk(translationUnit tu: CXTranslationUnit) {
        let root = clang_getTranslationUnitCursor(tu)
        clang_visitChildren(root, headerVisitorCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    func visit(cursor: CXCursor) -> CXChildVisitResult {
        let kind = clang_getCursorKind(cursor)

        switch kind {
        case CXCursor_FunctionDecl:
            guard isFromMainFile(cursor) else { return CXChildVisit_Continue }

            let name = cursorSpelling(cursor)
            guard !name.isEmpty else { return CXChildVisit_Continue }
            guard !name.hasPrefix("_") else { return CXChildVisit_Continue }

            let lower = name.lowercased()
            if lower.hasPrefix("vk") || lower.hasPrefix("gl") || lower.hasPrefix("mtl")
                || lower.hasPrefix("wgpu") || lower.hasPrefix("d3d")
            {
                return CXChildVisit_Continue
            }

            if clang_Cursor_getStorageClass(cursor) == CX_SC_Static { return CXChildVisit_Continue }
            if clang_Cursor_isFunctionInlined(cursor) != 0 { return CXChildVisit_Continue }

            let result = clang_getCursorResultType(cursor)
            if result.kind == CXType_Invalid { return CXChildVisit_Continue }

            guard !seenFunctions.contains(name) else { return CXChildVisit_Continue }
            seenFunctions.insert(name)

            let returnType = convertType(result)

            let numArgs = Int(clang_Cursor_getNumArguments(cursor))
            var params: [(name: String?, type: CKiraFFIType)] = []
            if numArgs > 0 {
                params.reserveCapacity(numArgs)
                for i in 0..<numArgs {
                    let arg = clang_Cursor_getArgument(cursor, UInt32(i))
                    let paramNameRaw = cursorSpelling(arg)
                    let paramName = paramNameRaw.isEmpty ? nil : paramNameRaw
                    let paramType = convertType(clang_getCursorType(arg))
                    params.append((name: paramName, type: paramType))
                }
            }

            parsed.functions.append(ParsedCFunction(name: name, returnType: returnType, parameters: params))
            return CXChildVisit_Continue

        case CXCursor_StructDecl:
            guard isFromMainFile(cursor) else { return CXChildVisit_Continue }

            let name = cursorSpelling(cursor)
            guard !name.isEmpty else { return CXChildVisit_Continue }
            guard !name.hasPrefix("(") else { return CXChildVisit_Continue }

            let fields = collectStructFields(cursor: cursor)

            if let idx = structIndexByName[name] {
                if parsed.structs[idx].fields.isEmpty && !fields.isEmpty {
                    parsed.structs[idx] = ParsedCStruct(name: name, fields: fields)
                }
            } else {
                structIndexByName[name] = parsed.structs.count
                parsed.structs.append(ParsedCStruct(name: name, fields: fields))
            }
            return CXChildVisit_Continue

        case CXCursor_EnumDecl:
            guard isFromMainFile(cursor) else { return CXChildVisit_Continue }

            let name = cursorSpelling(cursor)
            guard !name.isEmpty else { return CXChildVisit_Continue }
            guard !name.hasPrefix("(") else { return CXChildVisit_Continue }

            let cases = collectEnumCases(cursor: cursor)

            if let idx = enumIndexByName[name] {
                if parsed.enums[idx].cases.isEmpty && !cases.isEmpty {
                    parsed.enums[idx] = ParsedCEnum(name: name, cases: cases)
                }
            } else {
                enumIndexByName[name] = parsed.enums.count
                parsed.enums.append(ParsedCEnum(name: name, cases: cases))
            }
            return CXChildVisit_Continue

        case CXCursor_TypedefDecl:
            guard isFromMainFile(cursor) else { return CXChildVisit_Continue }

            let alias = cursorSpelling(cursor)
            guard !alias.isEmpty else { return CXChildVisit_Continue }
            guard !seenTypedefs.contains(alias) else { return CXChildVisit_Continue }

            let underlying = convertType(clang_getTypedefDeclUnderlyingType(cursor))

            // Skip function pointer typedefs (emitted as CPointer<CVoid> in-place).
            if case .functionPointer = underlying { return CXChildVisit_Continue }

            // Skip redundant typedefs like: typedef struct Foo Foo;
            if case .named(let n) = underlying, n == alias { return CXChildVisit_Continue }

            seenTypedefs.insert(alias)
            parsed.typedefs.append(ParsedCTypedef(alias: alias, underlying: underlying))
            return CXChildVisit_Continue

        default:
            return CXChildVisit_Continue
        }
    }

    private func collectStructFields(cursor: CXCursor) -> [(name: String, type: CKiraFFIType)] {
        let collector = FieldCollector()
        clang_visitChildren(cursor, fieldCollectorCallback, Unmanaged.passUnretained(collector).toOpaque())
        return collector.fields
    }

    private func collectEnumCases(cursor: CXCursor) -> [(name: String, value: Int64)] {
        let collector = EnumCaseCollector()
        clang_visitChildren(cursor, enumCaseCollectorCallback, Unmanaged.passUnretained(collector).toOpaque())
        return collector.cases
    }
}

private final class FieldCollector {
    var fields: [(name: String, type: CKiraFFIType)] = []

    func visit(cursor: CXCursor) -> CXChildVisitResult {
        if clang_getCursorKind(cursor) == CXCursor_FieldDecl {
            let name = cursorSpelling(cursor)
            if !name.isEmpty {
                let t = convertType(clang_getCursorType(cursor))
                fields.append((name: name, type: t))
            }
        }
        return CXChildVisit_Continue
    }
}

private final class EnumCaseCollector {
    var cases: [(name: String, value: Int64)] = []

    func visit(cursor: CXCursor) -> CXChildVisitResult {
        if clang_getCursorKind(cursor) == CXCursor_EnumConstantDecl {
            let name = cursorSpelling(cursor)
            if !name.isEmpty {
                cases.append((name: name, value: clang_getEnumConstantDeclValue(cursor)))
            }
        }
        return CXChildVisit_Continue
    }
}

private func headerVisitorCallback(
    cursor: CXCursor,
    parent: CXCursor,
    clientData: CXClientData?
) -> CXChildVisitResult {
    _ = parent
    guard let clientData else { return CXChildVisit_Continue }
    let visitor = Unmanaged<HeaderVisitor>.fromOpaque(clientData).takeUnretainedValue()
    return visitor.visit(cursor: cursor)
}

private func fieldCollectorCallback(
    cursor: CXCursor,
    parent: CXCursor,
    clientData: CXClientData?
) -> CXChildVisitResult {
    _ = parent
    guard let clientData else { return CXChildVisit_Continue }
    let collector = Unmanaged<FieldCollector>.fromOpaque(clientData).takeUnretainedValue()
    return collector.visit(cursor: cursor)
}

private func enumCaseCollectorCallback(
    cursor: CXCursor,
    parent: CXCursor,
    clientData: CXClientData?
) -> CXChildVisitResult {
    _ = parent
    guard let clientData else { return CXChildVisit_Continue }
    let collector = Unmanaged<EnumCaseCollector>.fromOpaque(clientData).takeUnretainedValue()
    return collector.visit(cursor: cursor)
}

private func isFromMainFile(_ cursor: CXCursor) -> Bool {
    clang_Location_isFromMainFile(clang_getCursorLocation(cursor)) != 0
}

private func cursorSpelling(_ cursor: CXCursor) -> String {
    cxStringToSwift(clang_getCursorSpelling(cursor))
}

private func typeSpelling(_ type: CXType) -> String {
    cxStringToSwift(clang_getTypeSpelling(type))
}

private func cxStringToSwift(_ str: CXString) -> String {
    guard let c = clang_getCString(str) else {
        clang_disposeString(str)
        return ""
    }
    let s = String(cString: c)
    clang_disposeString(str)
    return s
}

private func convertType(_ type: CXType) -> CKiraFFIType {
    switch type.kind {
    case CXType_Void:
        return .void
    case CXType_Bool:
        return .bool
    case CXType_Char_S, CXType_SChar:
        return .int8
    case CXType_Char_U, CXType_UChar:
        return .uint8
    case CXType_Short:
        return .int16
    case CXType_UShort:
        return .uint16
    case CXType_Int:
        return .int32
    case CXType_UInt:
        return .uint32
    case CXType_Long:
        return .int64
    case CXType_ULong:
        return .uint64
    case CXType_LongLong:
        return .int64
    case CXType_ULongLong:
        return .uint64
    case CXType_Float:
        return .float32
    case CXType_Double:
        return .float64
    case CXType_Pointer:
        let pointee = clang_getPointeeType(type)
        if pointee.kind == CXType_Void {
            return .opaquePointer
        }
        if pointee.kind == CXType_FunctionProto || pointee.kind == CXType_FunctionNoProto {
            return .functionPointer
        }
        if clang_isConstQualifiedType(pointee) != 0 {
            return .constPointer(convertType(pointee))
        }
        return .pointer(convertType(pointee))
    case CXType_ConstantArray, CXType_IncompleteArray:
        let elem = clang_getArrayElementType(type)
        return .pointer(convertType(elem))
    case CXType_Typedef:
        let decl = clang_getTypeDeclaration(type)
        if clang_Location_isFromMainFile(clang_getCursorLocation(decl)) == 0 {
            return convertType(clang_getCanonicalType(type))
        }
        let spelling = typeSpelling(type)
        let name = spelling.hasPrefix("const ") ? String(spelling.dropFirst(6)) : spelling
        return .named(name)
    case CXType_Elaborated:
        return convertType(clang_Type_getNamedType(type))
    case CXType_Record:
        let spelling = typeSpelling(type)
        let name = spelling
            .replacingOccurrences(of: "struct ", with: "")
            .replacingOccurrences(of: "union ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return .named(name)
    case CXType_Enum:
        return .int32
    case CXType_FunctionProto, CXType_FunctionNoProto:
        return .functionPointer
    default:
        let canonical = clang_getCanonicalType(type)
        if canonical.kind != type.kind {
            return convertType(canonical)
        }
        return .opaquePointer
    }
}

#endif

private func emitKira(parsed: ParsedHeader, libraryName: String, platform: BindgenPlatform) -> String {
    var out: [String] = []
    out.append("// Auto-generated by kira bindgen")
    out.append("// Library: \(libraryName)")
    out.append("// Platform: \(platform.nameForComment)")
    out.append("// Do not edit manually — regenerate with: kira bindgen <header.h> --lib \(libraryName)")
    out.append("")

    let structNames = Set(parsed.structs.map(\.name))
    let typedefAliases = Set(parsed.typedefs.map(\.alias))

    var normalTypedefs: [ParsedCTypedef] = []
    var opaquePointerTypedefs: [ParsedCTypedef] = []
    for td in parsed.typedefs {
        if isOpaquePointerTypedef(td, knownStructs: structNames, knownTypedefs: typedefAliases) {
            opaquePointerTypedefs.append(td)
        } else {
            normalTypedefs.append(td)
        }
    }

    for td in normalTypedefs {
        switch td.underlying {
        case .functionPointer, .opaquePointer:
            continue
        default:
            out.append("typealias \(td.alias) = \(typeToKiraString(td.underlying))")
        }
    }
    if !normalTypedefs.isEmpty { out.append("") }

    for s in parsed.structs {
        out.append("@CStruct")
        out.append("type \(s.name) {")
        for f in s.fields {
            out.append("    var \(f.name): \(typeToKiraString(f.type))")
        }
        out.append("}")
        out.append("")
    }

    for e in parsed.enums {
        out.append("@CEnum")
        out.append("type \(e.name) {")
        for c in e.cases {
            out.append("    \(c.name) = \(c.value)")
        }
        out.append("}")
        out.append("")
    }

    out.append("// Functions")
    for fn in parsed.functions {
        out.append("@ffi(lib: \"\(libraryName)\"\(platform.ffiLinkage))")

        var params: [String] = []
        params.reserveCapacity(fn.parameters.count)
        for (idx, p) in fn.parameters.enumerated() {
            let name = (p.name?.isEmpty == false) ? p.name! : "arg\(idx)"
            params.append("\(name): \(typeToKiraString(p.type))")
        }

        out.append("extern function \(fn.name)(\(params.joined(separator: ", "))) -> \(typeToKiraString(fn.returnType))")
        out.append("")
    }

    for td in opaquePointerTypedefs {
        out.append("typealias \(td.alias) = CPointer<CVoid>")
    }

    while out.last == "" { _ = out.popLast() }
    return out.joined(separator: "\n")
}

private func isOpaquePointerTypedef(_ td: ParsedCTypedef, knownStructs: Set<String>, knownTypedefs: Set<String>) -> Bool {
    switch td.underlying {
    case .opaquePointer:
        return true
    case .constPointer(let pointee), .pointer(let pointee):
        switch pointee {
        case .void:
            return true
        case .named(let n):
            if knownStructs.contains(n) { return false }
            if knownTypedefs.contains(n) { return false }
            return true
        default:
            return false
        }
    default:
        return false
    }
}

private func typeToKiraString(_ type: CKiraFFIType) -> String {
    switch type {
    case .void: return "CVoid"
    case .bool: return "CBool"
    case .int8: return "CInt8"
    case .int16: return "CInt16"
    case .int32: return "CInt32"
    case .int64: return "CInt64"
    case .uint8: return "CUInt8"
    case .uint16: return "CUInt16"
    case .uint32: return "CUInt32"
    case .uint64: return "CUInt64"
    case .float32: return "CFloat"
    case .float64: return "CDouble"
    case .pointer(let t): return "CPointer<\(typeToKiraString(t))>"
    case .constPointer(let t): return "CPointer<\(typeToKiraString(t))>"
    case .opaquePointer: return "CPointer<CVoid>"
    case .functionPointer: return "CPointer<CVoid>"
    case .named(let n): return n
    }
}

#if os(macOS) || os(iOS)
private func getSDKPath() -> String? {
    let task = Process()
    task.launchPath = "/usr/bin/xcrun"
    task.arguments = ["--show-sdk-path"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
#endif
