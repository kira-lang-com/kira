import XCTest
@testable import KiraCompiler

final class HotReloadTests: XCTestCase {
    func testStateSerializerRoundTrip() throws {
        struct S: Codable, Equatable { var x: Int; var y: String }
        let s = S(x: 1, y: "a")
        let ser = StateSerializer()
        let data = try ser.serialize(s)
        let back = try ser.deserialize(S.self, from: data)
        XCTAssertEqual(back, s)
    }
}

