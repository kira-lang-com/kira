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
    case fixedArray(count: Int, element: CKiraFFIType) // fixed-size array in a struct field
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

        let visitor = HeaderVisitor(allowedDir: headerDir)
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
        return "// error: libclang is not available. \(Self.libclangInstallHint())"
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

    private static func libclangInstallHint() -> String {
        #if os(macOS)
        return "Install LLVM: brew install llvm"
        #elseif os(Linux)
        return "Install libclang development headers, for example: sudo apt-get install libclang-dev"
        #elseif os(Windows)
        return "Install LLVM and make libclang available to SwiftPM on PATH."
        #else
        return "Install LLVM/libclang for your platform."
        #endif
    }
}

#if canImport(Clibclang)

private final class HeaderVisitor {
    var parsed = ParsedHeader()

    private var seenFunctions: Set<String> = []
    private var structIndexByName: [String: Int] = [:]
    private var enumIndexByName: [String: Int] = [:]
    private var seenTypedefs: Set<String> = []

    private let allowedDirPrefix: String

    init(allowedDir: String) {
        // Include the input header plus any headers in the same directory (project headers),
        // but exclude system headers. This is required for multi-header libraries (e.g. sokol_glue.h).
        if allowedDir.hasSuffix("/") {
            self.allowedDirPrefix = allowedDir
        } else {
            self.allowedDirPrefix = allowedDir + "/"
        }
    }

    func walk(translationUnit tu: CXTranslationUnit) {
        let root = clang_getTranslationUnitCursor(tu)
        clang_visitChildren(root, headerVisitorCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    private func isFromUserHeaders(_ cursor: CXCursor) -> Bool {
        let loc = clang_getCursorLocation(cursor)
        var file: CXFile?
        clang_getSpellingLocation(loc, &file, nil, nil, nil)
        guard let file else { return false }
        let path = cxStringToSwift(clang_getFileName(file))
        if path.isEmpty { return false }
        if path.hasPrefix(allowedDirPrefix) { return true }
        return false
    }

    func visit(cursor: CXCursor) -> CXChildVisitResult {
        let kind = clang_getCursorKind(cursor)

        switch kind {
        case CXCursor_FunctionDecl:
            guard isFromUserHeaders(cursor) else { return CXChildVisit_Continue }

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

            var returnType = convertType(result, context: .returnType, allowedDirPrefix: allowedDirPrefix)
            if functionReturnHasBoolKeyword(cursor, functionName: name) {
                returnType = applyBoolFixup(returnType)
            }

            let numArgs = Int(clang_Cursor_getNumArguments(cursor))
            var params: [(name: String?, type: CKiraFFIType)] = []
            if numArgs > 0 {
                params.reserveCapacity(numArgs)
                for i in 0..<numArgs {
                    let arg = clang_Cursor_getArgument(cursor, UInt32(i))
                    let paramNameRaw = cursorSpelling(arg)
                    let paramName = paramNameRaw.isEmpty ? nil : sanitizeKiraIdentifier(paramNameRaw)
                    var paramType = convertType(clang_getCursorType(arg), context: .functionParam, allowedDirPrefix: allowedDirPrefix)
                    if cursorHasBoolKeyword(arg) {
                        paramType = applyBoolFixup(paramType)
                    }
                    params.append((name: paramName, type: paramType))
                }
            }

            parsed.functions.append(ParsedCFunction(name: name, returnType: returnType, parameters: params))
            return CXChildVisit_Continue

        case CXCursor_StructDecl:
            guard isFromUserHeaders(cursor) else { return CXChildVisit_Continue }

            let name = cursorSpelling(cursor)
            guard isValidCDeclName(name) else { return CXChildVisit_Continue }

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
            guard isFromUserHeaders(cursor) else { return CXChildVisit_Continue }

            let name = cursorSpelling(cursor)
            guard isValidCDeclName(name) else { return CXChildVisit_Continue }

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
            guard isFromUserHeaders(cursor) else { return CXChildVisit_Continue }

            let alias = cursorSpelling(cursor)
            guard !alias.isEmpty else { return CXChildVisit_Continue }
            guard !seenTypedefs.contains(alias) else { return CXChildVisit_Continue }

            let underlying = convertType(clang_getTypedefDeclUnderlyingType(cursor), context: .typedefUnderlying, allowedDirPrefix: allowedDirPrefix)

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

    private func isValidCDeclName(_ name: String) -> Bool {
        if name.isEmpty { return false }
        if name.hasPrefix("(") { return false }
        if name.contains(" ") { return false }
        // libclang may surface anonymous declarations using a synthesized spelling like:
        // "enum (unnamed at file.h:line:col)".
        if name.contains("(anonymous") { return false }
        if name.contains("(unnamed") { return false }
        if name.hasPrefix("enum ") { return false }
        if name.hasPrefix("struct ") { return false }
        if name.hasPrefix("union ") { return false }
        return true
    }

    private func collectStructFields(cursor: CXCursor) -> [(name: String, type: CKiraFFIType)] {
        let collector = FieldCollector(allowedDirPrefix: allowedDirPrefix)
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
    private let allowedDirPrefix: String

    init(allowedDirPrefix: String) {
        self.allowedDirPrefix = allowedDirPrefix
    }

    func visit(cursor: CXCursor) -> CXChildVisitResult {
        if clang_getCursorKind(cursor) == CXCursor_FieldDecl {
            let name = sanitizeKiraIdentifier(cursorSpelling(cursor))
            if !name.isEmpty {
                var t = convertType(clang_getCursorType(cursor), context: .structField, allowedDirPrefix: allowedDirPrefix)
                if cursorHasBoolKeyword(cursor) {
                    t = applyBoolFixup(t)
                }
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
            let name = sanitizeKiraIdentifier(cursorSpelling(cursor))
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

private func tokenStrings(for cursor: CXCursor) -> [String] {
    let tu = clang_Cursor_getTranslationUnit(cursor)
    let range = clang_getCursorExtent(cursor)
    var tokens: UnsafeMutablePointer<CXToken>? = nil
    var numTokens: UInt32 = 0
    clang_tokenize(tu, range, &tokens, &numTokens)
    guard let tokens else { return [] }
    defer { clang_disposeTokens(tu, tokens, numTokens) }

    var out: [String] = []
    out.reserveCapacity(Int(numTokens))
    for i in 0..<Int(numTokens) {
        out.append(cxStringToSwift(clang_getTokenSpelling(tu, tokens.advanced(by: i).pointee)))
    }
    return out
}

private func cursorHasBoolKeyword(_ cursor: CXCursor) -> Bool {
    for t in tokenStrings(for: cursor) {
        if t == "bool" || t == "_Bool" { return true }
    }
    return false
}

private func functionReturnHasBoolKeyword(_ cursor: CXCursor, functionName: String) -> Bool {
    let toks = tokenStrings(for: cursor)
    guard let nameIndex = toks.firstIndex(of: functionName) else { return false }
    for t in toks[..<nameIndex] {
        if t == "bool" || t == "_Bool" { return true }
    }
    return false
}

private func applyBoolFixup(_ type: CKiraFFIType) -> CKiraFFIType {
    switch type {
    case .int32:
        return .bool
    case .pointer(let t):
        return .pointer(applyBoolFixup(t))
    case .constPointer(let t):
        return .constPointer(applyBoolFixup(t))
    case .fixedArray(let count, let element):
        return .fixedArray(count: count, element: applyBoolFixup(element))
    default:
        return type
    }
}

private func sanitizeKiraIdentifier(_ name: String) -> String {
    // `func` is a hard lexer error in Kira; other keywords should also be avoided in generated output.
    let reserved: Set<String> = [
        "func",
        "function",
        "type",
        "enum",
        "protocol",
        "construct",
        "extern",
        "import",
        "return",
        "if",
        "else",
        "let",
        "var",
        "async",
    ]
    if reserved.contains(name) {
        return name + "_"
    }
    return name
}

private enum TypeContext {
    case functionParam
    case returnType
    case structField
    case typedefUnderlying
}

private func convertType(_ type: CXType, context: TypeContext, allowedDirPrefix: String) -> CKiraFFIType {
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
        // On some platforms, libclang may report `bool` / `_Bool` as `int` when coming from `stdbool.h` macro expansion.
        let sp = typeSpelling(type)
        if sp == "bool" || sp == "_Bool" { return .bool }
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
            return .constPointer(convertType(pointee, context: context, allowedDirPrefix: allowedDirPrefix))
        }
        return .pointer(convertType(pointee, context: context, allowedDirPrefix: allowedDirPrefix))
    case CXType_ConstantArray, CXType_IncompleteArray:
        let elem = clang_getArrayElementType(type)
        if type.kind == CXType_ConstantArray,
           context == .structField || context == .typedefUnderlying
        {
            let count64 = clang_getArraySize(type)
            let count = Int(count64)
            if count > 0 {
                return .fixedArray(count: count, element: convertType(elem, context: .structField, allowedDirPrefix: allowedDirPrefix))
            }
        }
        // Arrays decay to pointers in function parameters and most other contexts.
        return .pointer(convertType(elem, context: context, allowedDirPrefix: allowedDirPrefix))
    case CXType_Typedef:
        // `bool` is typically a macro/type-alias in `stdbool.h`; treat it as C99 `_Bool` for correct ABI size (1 byte).
        do {
            let spelling = typeSpelling(type)
            let name = spelling.hasPrefix("const ") ? String(spelling.dropFirst(6)) : spelling
            if name == "bool" { return .bool }
        }

        let decl = clang_getTypeDeclaration(type)
        do {
            let loc = clang_getCursorLocation(decl)
            var file: CXFile?
            clang_getSpellingLocation(loc, &file, nil, nil, nil)
            if let file {
                let path = cxStringToSwift(clang_getFileName(file))
                if !path.isEmpty, !path.hasPrefix(allowedDirPrefix) {
                    return convertType(clang_getCanonicalType(type), context: context, allowedDirPrefix: allowedDirPrefix)
                }
            } else {
                return convertType(clang_getCanonicalType(type), context: context, allowedDirPrefix: allowedDirPrefix)
            }
        }
        let spelling = typeSpelling(type)
        let name = spelling.hasPrefix("const ") ? String(spelling.dropFirst(6)) : spelling
        return .named(name)
    case CXType_Elaborated:
        return convertType(clang_Type_getNamedType(type), context: context, allowedDirPrefix: allowedDirPrefix)
    case CXType_Record:
        var spelling = typeSpelling(type)
        if spelling.hasPrefix("const ") { spelling = String(spelling.dropFirst(6)) }
        if spelling.hasPrefix("volatile ") { spelling = String(spelling.dropFirst(9)) }
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
            return convertType(canonical, context: context, allowedDirPrefix: allowedDirPrefix)
        }
        return .opaquePointer
    }
}

#endif

private struct FixedArrayDef: Hashable {
    let count: Int
    let element: CKiraFFIType
    let elementSig: String

    init(count: Int, element: CKiraFFIType) {
        self.count = count
        self.element = element
        self.elementSig = typeSignature(element)
    }

    static func == (lhs: FixedArrayDef, rhs: FixedArrayDef) -> Bool {
        lhs.count == rhs.count && lhs.elementSig == rhs.elementSig
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        hasher.combine(elementSig)
    }
}

private func typeSignature(_ type: CKiraFFIType) -> String {
    switch type {
    case .void: return "void"
    case .bool: return "bool"
    case .int8: return "i8"
    case .int16: return "i16"
    case .int32: return "i32"
    case .int64: return "i64"
    case .uint8: return "u8"
    case .uint16: return "u16"
    case .uint32: return "u32"
    case .uint64: return "u64"
    case .float32: return "f32"
    case .float64: return "f64"
    case .pointer(let t): return "ptr(\(typeSignature(t)))"
    case .constPointer(let t): return "cptr(\(typeSignature(t)))"
    case .opaquePointer: return "opqptr"
    case .named(let n): return "named(\(n))"
    case .functionPointer: return "fnptr"
    case .fixedArray(let count, let element): return "arr\(count)(\(typeSignature(element)))"
    }
}

private func fnv1a32Hex(_ s: String) -> String {
    var hash: UInt32 = 2166136261
    for b in s.utf8 {
        hash ^= UInt32(b)
        hash = hash &* 16777619
    }
    return String(format: "%08x", hash)
}

private func sanitizeIdentifierFragment(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for scalar in s.unicodeScalars {
        if (scalar.value >= 48 && scalar.value <= 57) || // 0-9
            (scalar.value >= 65 && scalar.value <= 90) || // A-Z
            (scalar.value >= 97 && scalar.value <= 122) || // a-z
            scalar.value == 95 // _
        {
            out.unicodeScalars.append(scalar)
        } else {
            out.append("_")
        }
    }
    while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

private func fixedArrayTypeName(count: Int, element: CKiraFFIType) -> String {
    let elemFrag = sanitizeIdentifierFragment(typeToKiraString(element))
    let h = fnv1a32Hex("\(count)|\(typeSignature(element))")
    if elemFrag.isEmpty {
        return "CArray\(count)_\(h)"
    }
    return "CArray\(count)_\(elemFrag)_\(h)"
}

private func emitKira(parsed: ParsedHeader, libraryName: String, platform: BindgenPlatform) -> String {
    var out: [String] = []
    out.append("// Auto-generated by kira bindgen")
    out.append("// Library: \(libraryName)")
    out.append("// Platform: \(platform.nameForComment)")
    out.append("// Do not edit manually — regenerate with: kira bindgen <header.h> --lib \(libraryName)")
    out.append("")

    // Fixed-size arrays inside C structs are emitted as @CStruct wrappers so their layout matches C.
    var arrayDefs: Set<FixedArrayDef> = []
    func collectArrays(from type: CKiraFFIType) {
        switch type {
        case .fixedArray(let count, let element):
            arrayDefs.insert(.init(count: count, element: element))
            collectArrays(from: element)
        case .pointer(let t), .constPointer(let t):
            collectArrays(from: t)
        default:
            break
        }
    }
    for td in parsed.typedefs { collectArrays(from: td.underlying) }
    for s in parsed.structs {
        for f in s.fields { collectArrays(from: f.type) }
    }

    var orderedArrayDefs: [FixedArrayDef] = []
    orderedArrayDefs.reserveCapacity(arrayDefs.count)
    var visitedArrayDefs: Set<FixedArrayDef> = []
    func topoVisit(_ def: FixedArrayDef) {
        if visitedArrayDefs.contains(def) { return }
        visitedArrayDefs.insert(def)
        // Recursively walk element to find nested fixed arrays.
        func walkNested(_ t: CKiraFFIType) {
            switch t {
            case .fixedArray(let c, let e):
                topoVisit(.init(count: c, element: e))
            case .pointer(let p), .constPointer(let p):
                walkNested(p)
            default:
                break
            }
        }
        walkNested(def.element)
        orderedArrayDefs.append(def)
    }
    let sortedArrayDefs = arrayDefs.sorted {
        fixedArrayTypeName(count: $0.count, element: $0.element) < fixedArrayTypeName(count: $1.count, element: $1.element)
    }
    for def in sortedArrayDefs {
        topoVisit(def)
    }

    for def in orderedArrayDefs {
        out.append("@CStruct")
        out.append("type \(fixedArrayTypeName(count: def.count, element: def.element)) {")
        for i in 0..<def.count {
            out.append("    var _\(i): \(typeToKiraString(def.element))")
        }
        out.append("}")
        out.append("")
    }

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

    if !parsed.enums.isEmpty {
        out.append("// Enum constants (C enums are represented as CInt32 at the ABI level)")
        var seen: Set<String> = []
        for e in parsed.enums {
            for c in e.cases {
                if seen.contains(c.name) { continue }
                seen.insert(c.name)
                out.append("let \(c.name) = \(c.value)")
            }
        }
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
    case .fixedArray(let count, let element):
        return fixedArrayTypeName(count: count, element: element)
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
