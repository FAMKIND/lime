#if DEBUG
import UIKit

/// Shares log files with the iOS share sheet. LIME-103's sheet (a SwiftUI `.sheet` wrapping the controller, over
/// the app's own Documents files) came up blank on both phones, so this presents the controller straight from the
/// top view controller, with copies in the temporary folder. If it is still blank, the logs can be copied over USB:
/// see "Nearby test logs" in ios/README.md.
@MainActor
enum NearbyShare {
    static func present(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let folder = URL.temporaryDirectory.appending(path: "nearby-share-\(Int(Date().timeIntervalSince1970))", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copies = urls.compactMap { url -> URL? in
            let copy = folder.appending(path: url.lastPathComponent)
            return (try? FileManager.default.copyItem(at: url, to: copy)) == nil ? nil : copy
        }
        guard !copies.isEmpty, let top = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: copies, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
#endif
