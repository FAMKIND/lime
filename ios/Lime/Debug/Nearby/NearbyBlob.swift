#if DEBUG
import CryptoKit
import Foundation

/// The test payload: random bytes, signed so the receiver can verify them. No message, no user data and
/// no secret travels: the public key and signature are the only identity, and the key is a throwaway made
/// for this spike (kept in this phone's settings), not the account's.
///
/// A blob is `public key (32) | signature (64) | sent-at ms (8) | body`; the signature covers sent-at and body.
enum NearbyBlob {
    static let sizes = [200, 4_096, 32_768]
    static let overhead = 32 + 64 + 8

    private static let keyName = "lime.nearby.spikeKey"

    /// This phone's throwaway signing key.
    static func signingKey() -> Curve25519.Signing.PrivateKey {
        if let text = UserDefaults.standard.string(forKey: keyName), let raw = Data(base64Encoded: text),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) { return key }
        let key = Curve25519.Signing.PrivateKey()
        UserDefaults.standard.set(key.rawRepresentation.base64EncodedString(), forKey: keyName)
        return key
    }

    static func make(bodySize: Int, key: Curve25519.Signing.PrivateKey, now: Date = Date()) -> Data {
        var signed = Data()
        var sentAt = UInt64(now.timeIntervalSince1970 * 1000).bigEndian
        withUnsafeBytes(of: &sentAt) { signed.append(contentsOf: $0) }
        signed.append(Data((0..<bodySize).map { _ in UInt8.random(in: 0...255) }))
        let signature = (try? key.signature(for: signed)) ?? Data(count: 64)
        return key.publicKey.rawRepresentation + signature + signed
    }

    struct Parsed: Equatable {
        let valid: Bool
        let bodySize: Int
        let sentAtMs: Int64
        /// A short, non-identifying tag of the signer (first 4 bytes of the key's hash).
        let signer: String
    }

    static func parse(_ blob: Data) -> Parsed? {
        guard blob.count >= overhead else { return nil }
        let keyBytes = blob.prefix(32), signature = blob.dropFirst(32).prefix(64), signed = blob.dropFirst(96)
        let valid = (try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes))
            .map { $0.isValidSignature(signature, for: signed) } ?? false
        let sentAt = signed.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Parsed(valid: valid, bodySize: blob.count - overhead, sentAtMs: Int64(bitPattern: sentAt), signer: fingerprint(Data(keyBytes)))
    }

    /// The first 8 bytes of the blob's SHA-256, as hex: what de-duplication and the log call the blob.
    static func id(of blob: Data) -> String { SHA256.hash(data: blob).prefix(8).map { String(format: "%02x", $0) }.joined() }

    static func fingerprint(_ key: Data) -> String { SHA256.hash(data: key).prefix(4).map { String(format: "%02x", $0) }.joined() }
}

/// Frames on a byte stream: `length (4, big endian) | type (1) | payload`. The length covers type and payload.
enum NearbyFrame {
    enum Kind: UInt8 { case hello = 1, blob = 2 }

    static func encode(_ kind: Kind, _ payload: Data) -> Data {
        var length = UInt32(payload.count + 1).bigEndian
        var data = Data()
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(kind.rawValue)
        data.append(payload)
        return data
    }
}

/// Collects stream bytes into whole frames.
struct NearbyFrameReader {
    private var buffer = Data()
    /// When the first byte of the frame being collected arrived.
    private(set) var startedAt: Date?

    mutating func append(_ data: Data, now: Date = Date()) -> [(NearbyFrame.Kind, Data, Date)] {
        if buffer.isEmpty { startedAt = now }
        buffer.append(data)
        var frames: [(NearbyFrame.Kind, Data, Date)] = []
        while buffer.count >= 5 {
            let length = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            // A length that cannot be real: drop the stream's buffer rather than wait for ever.
            guard length >= 1, length <= 1_000_000 else { buffer = Data(); startedAt = nil; return frames }
            guard buffer.count >= 4 + length else { break }
            let body = buffer.dropFirst(4).prefix(length)
            let began = startedAt ?? now
            if let kind = NearbyFrame.Kind(rawValue: body.first ?? 0) { frames.append((kind, Data(body.dropFirst()), began)) }
            buffer = Data(buffer.dropFirst(4 + length))
            startedAt = buffer.isEmpty ? nil : now
        }
        return frames
    }
}
#endif
