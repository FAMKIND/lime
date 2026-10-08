#if DEBUG
import CryptoKit
import XCTest
@testable import Lime

/// The Bluetooth field test's own parts that need no Bluetooth: the signed test blob, the framing, the log.
final class NearbyBlobTests: XCTestCase {
    func testABlobIsSignedAndVerifies() throws {
        let key = Curve25519.Signing.PrivateKey()
        for size in NearbyBlob.sizes {
            let blob = NearbyBlob.make(bodySize: size, key: key)
            XCTAssertEqual(blob.count, size + NearbyBlob.overhead)
            let parsed = try XCTUnwrap(NearbyBlob.parse(blob))
            XCTAssertTrue(parsed.valid, "\(size) B")
            XCTAssertEqual(parsed.bodySize, size)
            XCTAssertEqual(parsed.signer, NearbyBlob.fingerprint(key.publicKey.rawRepresentation))
        }
    }

    func testATamperedOrTruncatedBlobIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        var blob = NearbyBlob.make(bodySize: 200, key: key)
        blob[blob.count - 1] ^= 0xFF
        XCTAssertEqual(NearbyBlob.parse(blob)?.valid, false, "one flipped bit fails the signature")
        XCTAssertNil(NearbyBlob.parse(Data(count: 50)), "too short to be a blob")
        // A different key's signature does not verify against this key's blob.
        let other = NearbyBlob.make(bodySize: 200, key: Curve25519.Signing.PrivateKey())
        var spliced = other
        spliced.replaceSubrange(0..<32, with: key.publicKey.rawRepresentation)
        XCTAssertEqual(NearbyBlob.parse(spliced)?.valid, false)
    }

    func testTheBlobCarriesNothingButRandomBytesAndTheSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let a = NearbyBlob.make(bodySize: 200, key: key), b = NearbyBlob.make(bodySize: 200, key: key)
        XCTAssertNotEqual(NearbyBlob.id(of: a), NearbyBlob.id(of: b), "random: two blobs are never the same")
        XCTAssertEqual(NearbyBlob.id(of: a), NearbyBlob.id(of: a), "the id is stable, for de-duplication")
        XCTAssertEqual(NearbyBlob.id(of: a).count, 16)
        let sent = try XCTUnwrap(NearbyBlob.parse(a)).sentAtMs
        XCTAssertEqual(Double(sent), Date().timeIntervalSince1970 * 1000, accuracy: 5_000)
    }

    func testFramesSurviveBeingCutIntoAnyChunks() {
        let blob = NearbyBlob.make(bodySize: 4_096, key: Curve25519.Signing.PrivateKey())
        let stream = NearbyFrame.encode(.hello, Data("abcd1234".utf8)) + NearbyFrame.encode(.blob, blob) + NearbyFrame.encode(.blob, Data([1, 2, 3]))
        for chunk in [1, 7, 20, 185, 512, 5_000] {
            var reader = NearbyFrameReader()
            var frames: [(NearbyFrame.Kind, Data)] = []
            var offset = 0
            while offset < stream.count {
                let end = min(offset + chunk, stream.count)
                frames += reader.append(stream.subdata(in: offset..<end)).map { ($0.0, $0.1) }
                offset = end
            }
            XCTAssertEqual(frames.map(\.0), [.hello, .blob, .blob], "chunk \(chunk)")
            XCTAssertEqual(String(decoding: frames[0].1, as: UTF8.self), "abcd1234")
            XCTAssertEqual(frames[1].1, blob, "chunk \(chunk)")
        }
    }

    func testAnImpossibleLengthIsDroppedNotWaitedFor() {
        var reader = NearbyFrameReader()
        XCTAssertTrue(reader.append(Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])).isEmpty)
        let good = NearbyFrame.encode(.hello, Data("x".utf8))
        XCTAssertEqual(reader.append(good).count, 1, "the reader recovers on the next frame")
    }

    @MainActor
    func testTheLogWritesOneJsonObjectPerLineWithTheScenarioAndNoPersonalData() throws {
        let log = NearbyLog()
        log.begin(label: "2-A open/B background", extra: ["tag": "ab12"])
        log.record("discovered", ["rssi": -60, "peer": "1234abcd"])
        log.record("send_done", ["bytes": 204, "ms": 40])
        log.end(summary: ["sent": 1])
        let url = try XCTUnwrap(log.fileURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4)
        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(header["kind"] as? String, "header")
        XCTAssertEqual(header["scenario"] as? String, "2-A open/B background")
        XCTAssertNotNil(header["device"]); XCTAssertNotNil(header["ios"]); XCTAssertNotNil(header["battery"])
        XCTAssertEqual(Set(header.keys).intersection(["name", "email", "username", "userId", "token"]), [], "no personal data")
        for line in lines { XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]) }
        XCTAssertTrue(url.lastPathComponent.hasPrefix("nearby-2-A_open_B_background-"), url.lastPathComponent)
    }
}
#endif
