import XCTest
@testable import Lime

final class StorageFolderNameTests: XCTestCase {
    private func support() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func names(_ url: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }

    func testTheOldFolderReallyReadsLowercaseAfterwards() throws {
        let dir = try support()
        let old = dir.appendingPathComponent("Lime", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: old.appendingPathComponent("lime.db"))
        try StorageBootstrap.Location.renameOldFolder(in: dir)
        XCTAssertEqual(names(dir), ["lime"], "the name on disk changed case, not just the lookup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("lime/lime.db").path), "and the files came with it")
    }

    func testNothingHappensWhenThereIsNoOldFolderAndTheNewOneIsLeftAlone() throws {
        let dir = try support()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("lime"), withIntermediateDirectories: true)
        try StorageBootstrap.Location.renameOldFolder(in: dir)
        XCTAssertEqual(names(dir), ["lime"])
    }
}
