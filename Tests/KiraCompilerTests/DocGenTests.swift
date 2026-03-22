import XCTest
@testable import KiraCompiler

final class DocGenTests: XCTestCase {
    private func typedModule(_ text: String) throws -> TypedModule {
        let src = SourceText(file: "docs.kira", text: text)
        return try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64)).typed
    }

    func testDocExtractionFromType() throws {
        let typed = try typedModule("""
        @Doc("A color value.
        Keeps channels in normalized 0.0 to 1.0 space.")
        type Color {
            @Doc("The red channel.")
            var r: Float = 0.0
        }
        """)

        let symbols = DocExtractor().extract(from: typed, moduleName: "Docs")
        let color = try XCTUnwrap(symbols.first(where: { $0.name == "Color" }))
        XCTAssertEqual(color.kind, .type)
        XCTAssertEqual(color.properties.count, 1)
        XCTAssertEqual(color.properties[0].doc, "The red channel.")
        XCTAssertTrue(color.doc?.contains("normalized 0.0 to 1.0 space.") == true)
    }

    func testDocExtractionFromMethodsAndStatics() throws {
        let typed = try typedModule("""
        type Rectangle {
            @Doc("Compute the area.
            Multiplies width by height.")
            function area(width: Float, height: Float) -> Float {
                return width * height
            }

            @Doc("Return the canonical unit rectangle.")
            static function unit() -> Rectangle {
                return Rectangle()
            }
        }
        """)

        let symbols = DocExtractor().extract(from: typed, moduleName: "Docs")
        let rectangle = try XCTUnwrap(symbols.first(where: { $0.name == "Rectangle" }))
        XCTAssertEqual(rectangle.methods.count, 2)
        XCTAssertTrue(rectangle.methods.contains(where: { $0.signature == "function area(width: Float, height: Float) -> Float" }))
        XCTAssertTrue(rectangle.methods.contains(where: { $0.signature == "static function unit() -> Rectangle" }))
    }

    func testDocExtractionFromEnumAndProtocol() throws {
        let typed = try typedModule("""
        @Doc("How content sizes itself.")
        enum SizeMode {
            @Doc("Use the exact value.")
            case fixed(value: Float)
            case fill
        }

        protocol Widget {
            @Doc("Draw the widget.
            Called after layout completes.")
            function draw() -> Void
        }
        """)

        let symbols = DocExtractor().extract(from: typed, moduleName: "Docs")
        let enumSymbol = try XCTUnwrap(symbols.first(where: { $0.name == "SizeMode" }))
        XCTAssertEqual(enumSymbol.variants.count, 2)
        XCTAssertEqual(enumSymbol.variants.first?.signature, "fixed(value: Float)")
        XCTAssertEqual(enumSymbol.variants.first?.doc, "Use the exact value.")

        let protocolSymbol = try XCTUnwrap(symbols.first(where: { $0.name == "Widget" }))
        XCTAssertEqual(protocolSymbol.requirements.count, 1)
        XCTAssertEqual(protocolSymbol.requirements[0].signature, "function draw() -> Void")
        XCTAssertTrue(protocolSymbol.requirements[0].doc?.contains("layout completes.") == true)
    }

    func testRendererIncludesSeparateFenceSections() {
        let symbol = DocSymbol(
            kind: .type,
            moduleName: "Docs",
            name: "LayoutEngine",
            doc: "Measure first.\nPlace second.",
            properties: [.init(name: "padding", signature: "Float", doc: "Padding in points.")],
            methods: [.init(name: "update", signature: "function update() -> Void", doc: "Update the tree.")],
            variants: [],
            requirements: []
        )

        let rendered = DocRenderer().render(symbol: symbol)
        XCTAssertTrue(rendered.contains("<!-- kira:generated:start -->"))
        XCTAssertTrue(rendered.contains("<!-- kira:generated:methods:start -->"))
        XCTAssertTrue(rendered.contains("Measure first.\nPlace second."))
    }

    func testFenceSafetyModel() throws {
        let renderer = DocRenderer()
        let symbol = DocSymbol(
            kind: .type,
            moduleName: "Docs",
            name: "LayoutEngine",
            doc: "First doc block.",
            properties: [.init(name: "padding", signature: "Float", doc: "Padding.")],
            methods: [.init(name: "update", signature: "function update() -> Void", doc: "Update.")],
            variants: [],
            requirements: []
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("LayoutEngine.md")
        try renderer.writeFenceSafe(rendered: renderer.render(symbol: symbol), to: url, force: false)

        let manual = """
        # LayoutEngine

        Manual intro.

        ## Properties

        <!-- kira:generated:start -->
        stale
        <!-- kira:generated:end -->

        Manual footer.

        ## Methods

        <!-- kira:generated:methods:start -->
        stale methods
        <!-- kira:generated:methods:end -->
        """
        try manual.write(to: url, atomically: true, encoding: .utf8)

        let updated = DocSymbol(
            kind: .type,
            moduleName: "Docs",
            name: "LayoutEngine",
            doc: "Updated doc block.",
            properties: [.init(name: "spacing", signature: "Float", doc: "Spacing.")],
            methods: [.init(name: "measure", signature: "function measure() -> Void", doc: "Measure.")],
            variants: [],
            requirements: []
        )
        try renderer.writeFenceSafe(rendered: renderer.render(symbol: updated), to: url, force: false)

        let final = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(final.contains("Manual intro."))
        XCTAssertTrue(final.contains("Manual footer."))
        XCTAssertTrue(final.contains("### spacing"))
        XCTAssertTrue(final.contains("### measure"))
        XCTAssertFalse(final.contains("stale methods"))
    }
}
