import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The invite text and link a teacher sends from their own phone. Lime's servers never send invites
/// and never learn who was invited.
enum InviteLink {
    static let host = "limechat.org"

    static func url(username: String) -> String { "https://\(host)/u/\(username)" }

    static func message(username: String) -> String {
        "Join me on Lime, a private messenger made for teachers: \(url(username: username))"
    }

    /// The same text for someone with no username yet: just the site.
    static let generalMessage = "Join me on Lime, a private messenger made for teachers: https://\(host)"
}

/// What a teacher's QR code holds: their invite link plus their identity-key fingerprint, e.g.
/// `https://limechat.org/u/grace.h?k=A1B2C3D4E5F607182930`. A phone camera that scans it opens the
/// invite page; Lime reads the fingerprint too.
@MainActor
struct QRPayload: Equatable {
    /// 20 upper-case hex digits (the first ten bytes of SHA-256 of the master key), no spaces.
    let fingerprint: String?
    let username: String

    init(username: String, fingerprint: String?) {
        self.username = username
        self.fingerprint = fingerprint.flatMap(Self.compact)
    }

    var text: String {
        var link = InviteLink.url(username: username)
        if let fingerprint { link += "?k=\(fingerprint)" }
        return link
    }

    /// Reads a scanned string: only Lime's own invite links with a valid username (and, when present,
    /// a well-formed fingerprint). Anything else is not a Lime QR code.
    static func decode(_ text: String) -> QRPayload? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https",
              let host = components.host?.lowercased(), host == InviteLink.host || host == "www.\(InviteLink.host)" else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2, parts[0] == "u", OnboardingModel.usernameError(parts[1]) == nil else { return nil }
        let key = components.queryItems?.first { $0.name == "k" }?.value
        if let key {
            guard let fingerprint = compact(key) else { return nil }
            return QRPayload(username: parts[1], fingerprint: fingerprint)
        }
        return QRPayload(username: parts[1], fingerprint: nil)
    }

    /// 20 hex digits, upper case, no spaces; `nil` when `text` is not one.
    static func compact(_ text: String) -> String? {
        let digits = text.filter { !$0.isWhitespace }.uppercased()
        guard digits.count == 20, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return digits
    }
}

/// QR images, drawn and read with Core Image (no camera needed to test the round trip).
@MainActor
enum QRImage {
    /// A crisp black-on-white QR code for `text`, `size` points square.
    static func make(_ text: String, size: CGFloat = 260) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = ceil(size * UIScreen.main.scale / output.extent.width)
        let big = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(big, from: big.extent) else { return nil }
        return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
    }

    /// The text of the first QR code in the image, if any.
    static func read(_ image: UIImage) -> String? {
        guard let ci = image.ciImage ?? image.cgImage.map({ CIImage(cgImage: $0) }) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: ci).first as? CIQRCodeFeature)?.messageString
    }
}

/// What a scan told us about the person (the fingerprint compared with the server's key).
enum ScanVerdict: Equatable {
    /// The code matches the key the server holds: verified in person.
    case verified
    /// The code does not match the server's key: a warning, and nothing is marked verified.
    case mismatch
    /// The code matches, but it is not the key we remembered: accept the key change first.
    case keyChanged
    /// A plain invite link with no fingerprint: nothing to compare.
    case unchecked
}
