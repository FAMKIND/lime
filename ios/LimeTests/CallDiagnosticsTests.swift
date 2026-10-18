import XCTest
@testable import Lime

/// LIME-166 (review finding F-05): the call diagnostics log is a file only in a Debug build; in Release it is in memory only.
@MainActor
final class CallDiagnosticsTests: XCTestCase {
    private var url: URL!

    override func setUp() async throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).log")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: url) }

    func testInMemoryModeKeepsTheLinesButWritesNoFileAndRemovesAnOldOne() throws {
        try Data("old build line".utf8).write(to: url)
        let diagnostics = CallDiagnostics(url: url, persists: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "a file an earlier build left is removed")
        diagnostics.log("call started")
        diagnostics.log("call ended")
        XCTAssertEqual(diagnostics.lines.count, 2, "the lines are there for this run")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing is ever written")
    }

    func testFileModeWritesAndReadsBackAcrossARestart() throws {
        let first = CallDiagnostics(url: url, persists: true)
        first.log("ringing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let second = CallDiagnostics(url: url, persists: true)
        XCTAssertEqual(second.lines.count, 1)
        XCTAssertTrue(second.text.hasSuffix("ringing"))
    }

    func testThisBuildPersistsOnlyInDebug() {
        #if DEBUG
        XCTAssertTrue(CallDiagnostics.persistsByDefault)
        #else
        XCTAssertFalse(CallDiagnostics.persistsByDefault)
        #endif
    }
}
