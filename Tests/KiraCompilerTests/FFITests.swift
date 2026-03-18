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
}

