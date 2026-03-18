import XCTest
@testable import KiraCompiler

final class FFITests: XCTestCase {
    func testBindgenGeneratesExternFunction() {
        let header = "int add(int a, int b);\n"
        let kira = BindgenEngine().generate(headerText: header, libraryName: "libtest")

        #if canImport(Clibclang)
        XCTAssertTrue(kira.contains("extern function add"))
        XCTAssertFalse(kira.contains("func "))
        #else
        XCTAssertTrue(kira.contains("libclang is not available"))
        #endif
    }

    func testBindgenUsesStableFixedArrayNames() {
        let header = """
        typedef struct sg_buffer { unsigned int id; } sg_buffer;
        typedef struct holder { sg_buffer buffers[8]; } holder;
        """
        let kira = BindgenEngine().generate(headerText: header, libraryName: "libtest")

        #if canImport(Clibclang)
        XCTAssertTrue(kira.contains("type CArray8_sg_buffer {"))
        XCTAssertFalse(kira.contains("CArray8_sg_buffer_"))
        #else
        XCTAssertTrue(kira.contains("libclang is not available"))
        #endif
    }
}
