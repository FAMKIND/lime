import XCTest
@testable import Lime

/// Invite text, QR payloads (encode, decode, rejections) and the QR image round trip.
@MainActor
final class InviteTests: XCTestCase {
    private let code = "A1B2C3D4E5F607182930"

    func testTheInviteTextNamesTheInviterAndCarriesThePersonalLink() {
        XCTAssertEqual(InviteLink.message(username: "grace.h"),
                       "Join me on Lime, a private messenger made for teachers: https://limechat.org/u/grace.h")
        XCTAssertTrue(InviteLink.generalMessage.hasPrefix("Join me on Lime, a private messenger made for teachers: https://limechat.org"))
    }

    func testAPayloadRoundTripsThroughItsText() throws {
        let payload = QRPayload(username: "grace.h", fingerprint: "a1b2 c3d4 e5f6 0718 2930")
        XCTAssertEqual(payload.fingerprint, code, "spaces and case are normalised")
        XCTAssertEqual(payload.text, "https://limechat.org/u/grace.h?k=\(code)")
        XCTAssertEqual(QRPayload.decode(payload.text), payload)
    }

    func testAPlainInviteLinkHasNoFingerprint() throws {
        let decoded = try XCTUnwrap(QRPayload.decode("https://limechat.org/u/grace.h"))
        XCTAssertEqual(decoded.username, "grace.h")
        XCTAssertNil(decoded.fingerprint)
    }

    func testOnlyLimeLinksWithAGoodUsernameAndKeyAreAccepted() {
        for bad in ["", "hello", "http://limechat.org/u/grace.h", "https://example.com/u/grace.h", "https://limechat.org/grace.h",
                    "https://limechat.org/u/", "https://limechat.org/u/a b", "https://limechat.org/u/admin",
                    "https://limechat.org/u/grace.h?k=XYZ", "https://limechat.org/u/grace.h?k=A1B2", "https://limechat.org/u/grace.h/extra",
                    "https://limechat.org.evil.com/u/grace.h?k=\(code)"] {
            XCTAssertNil(QRPayload.decode(bad), bad)
        }
        XCTAssertNotNil(QRPayload.decode("  https://www.limechat.org/u/grace.h?k=\(code.lowercased())\n"))
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
