import XCTest
@testable import KiraDebugRuntime

final class PatchCompatibilityTests: XCTestCase {
    func testImplementationOnlyChangeIsHotPatchable() {
        let current = KiraRuntimeCompatibilitySnapshot(manifest: makeManifest(
            functionHash: "a",
            typeHash: "t1",
            implHash: "impl-1",
            runtimeABI: 1,
            hostABI: 1,
            bytecode: 1
        ))
        let incoming = makeManifest(functionHash: "a", typeHash: "t1", implHash: "impl-2", runtimeABI: 1, hostABI: 1, bytecode: 1)

        let decision = KiraPatchCompatibilityEvaluator.evaluate(current: current, incoming: incoming)

        XCTAssertEqual(decision.level, .hotPatch)
    }

    func testSignatureChangeRequiresSoftReboot() {
        let current = makeSnapshot(functionHash: "a", typeHash: "t1", runtimeABI: 1, hostABI: 1, bytecode: 1)
        let incoming = makeManifest(functionHash: "b", typeHash: "t1", implHash: "impl-2", runtimeABI: 1, hostABI: 1, bytecode: 1)

        let decision = KiraPatchCompatibilityEvaluator.evaluate(current: current, incoming: incoming)

        XCTAssertEqual(decision.level, .softReboot)
        XCTAssertTrue(decision.reasons.contains("exported function signatures changed"))
    }

    func testHostBridgeABIChangeRequiresFullRelaunch() {
        let current = makeSnapshot(functionHash: "a", typeHash: "t1", runtimeABI: 1, hostABI: 1, bytecode: 1)
        let incoming = makeManifest(functionHash: "a", typeHash: "t1", implHash: "impl-2", runtimeABI: 1, hostABI: 2, bytecode: 1)

        let decision = KiraPatchCompatibilityEvaluator.evaluate(current: current, incoming: incoming)

        XCTAssertEqual(decision.level, .fullRelaunchRequired)
        XCTAssertTrue(decision.reasons.contains("host bridge ABI version changed"))
    }

    private func makeSnapshot(functionHash: String, typeHash: String, runtimeABI: Int, hostABI: Int, bytecode: Int) -> KiraRuntimeCompatibilitySnapshot {
        KiraRuntimeCompatibilitySnapshot(
            targetAppIdentifier: "com.kira.tests",
            runtimeABIVersion: runtimeABI,
            bytecodeFormatVersion: bytecode,
            hostBridgeABIVersion: hostABI,
            exportedFunctions: [.init(name: "main", signatureHash: functionHash)],
            publicTypes: [.init(name: "App", layoutHash: typeHash, conformanceHash: "c1")],
            bridgeVisibleSymbols: ["main", "graphics_on_frame"],
            moduleImplementationHashes: ["main": "impl-1"]
        )
    }

    private func makeManifest(functionHash: String, typeHash: String, implHash: String, runtimeABI: Int, hostABI: Int, bytecode: Int) -> KiraPatchManifest {
        KiraPatchManifest(
            sessionID: "session",
            generation: 1,
            targetAppIdentifier: "com.kira.tests",
            projectName: "Tests",
            runtimeABIVersion: runtimeABI,
            bytecodeFormatVersion: bytecode,
            hostBridgeABIVersion: hostABI,
            changedModules: ["main"],
            dependencyClosure: ["main"],
            modules: [
                .init(
                    moduleName: "main",
                    sourceFiles: ["/tmp/main.kira"],
                    exportedFunctions: [.init(name: "main", signatureHash: functionHash)],
                    publicTypes: [.init(name: "App", layoutHash: typeHash, conformanceHash: "c1")],
                    bridgeVisibleSymbols: ["main", "graphics_on_frame"],
                    implementationHash: implHash
                )
            ],
            metadataHash: "meta",
            integrityHash: "integrity",
            sessionSignature: "sig",
            createdAtEpochMillis: 0
        )
    }
}
