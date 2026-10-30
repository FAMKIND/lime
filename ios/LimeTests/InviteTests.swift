import XCTest
@testable import Lime

/// Invite text, QR payloads (encode, decode, rejections) and the QR image round trip.
@MainActor
final class InviteTests: XCTestCase {
    private let code = "A1B2C3D4E5F607182930"

    func testTheInviteTextNamesTheInviterAndCarriesThePersonalLink() {
        XCTAssertEqual(InviteLink.message(username: "grace.h"),
                       "Join me on lime, a private messenger made for teachers: https://limemessenger.com/u/grace.h")
        XCTAssertTrue(InviteLink.generalMessage.hasPrefix("Join me on lime, a private messenger made for teachers: https://limemessenger.com"))
    }

    func testAPayloadRoundTripsThroughItsText() throws {
        let payload = QRPayload(username: "grace.h", fingerprint: "a1b2 c3d4 e5f6 0718 2930")
        XCTAssertEqual(payload.fingerprint, code, "spaces and case are normalised")
        XCTAssertEqual(payload.text, "https://limemessenger.com/u/grace.h?k=\(code)")
        XCTAssertEqual(QRPayload.decode(payload.text), payload)
    }

    func testAPlainInviteLinkHasNoFingerprint() throws {
        let decoded = try XCTUnwrap(QRPayload.decode("https://limemessenger.com/u/grace.h"))
        XCTAssertEqual(decoded.username, "grace.h")
        XCTAssertNil(decoded.fingerprint)
    }

    func testOnlyLimeLinksWithAGoodUsernameAndKeyAreAccepted() {
        for bad in ["", "hello", "http://limemessenger.com/u/grace.h", "https://example.com/u/grace.h", "https://limemessenger.com/grace.h",
                    "https://limemessenger.com/u/", "https://limemessenger.com/u/a b", "https://limemessenger.com/u/admin",
                    "https://limemessenger.com/u/grace.h?k=XYZ", "https://limemessenger.com/u/grace.h?k=A1B2", "https://limemessenger.com/u/grace.h/extra",
                    "https://limemessenger.com.evil.com/u/grace.h?k=\(code)"] {
            XCTAssertNil(QRPayload.decode(bad), bad)
        }
        XCTAssertNotNil(QRPayload.decode("  https://www.limemessenger.com/u/grace.h?k=\(code.lowercased())\n"))
    }

    /// LIME-172b: lime lives on limemessenger.com; a link to the retired limechat.org (or its www) is not an invite.
    func testALinkToTheOldHostIsNotAnInvite() {
        for old in ["https://limechat.org/u/grace.h", "https://www.limechat.org/u/grace.h?k=\(code)", "https://turn.limechat.org/u/grace.h"] {
            XCTAssertNil(QRPayload.decode(old), old)
        }
    }

    func testAQRImageReadsBackToTheSameText() throws {
        let text = QRPayload(username: "grace.h", fingerprint: code).text
        let image = try XCTUnwrap(QRImage.make(text))
        XCTAssertEqual(QRImage.read(image), text)
        XCTAssertEqual(QRPayload.decode(try XCTUnwrap(QRImage.read(image)))?.fingerprint, code)
    }

    func testTheDemoPersonVerifiesOnlyWithTheirOwnCode() async throws {
        let store = ConversationStore()
        store.loadDemo(screen: "scan-verified")
        let found = try await store.find("grace.h")
        let person = try XCTUnwrap(found)
        let good = try await store.verifyInPerson(userId: person.userId, fingerprint: ConversationStore.demoGraceFingerprint)
        XCTAssertEqual(good, .verified)
        let bad = try await store.verifyInPerson(userId: person.userId, fingerprint: "0000111122223333FFFF")
        XCTAssertEqual(bad, .mismatch)
    }
}
