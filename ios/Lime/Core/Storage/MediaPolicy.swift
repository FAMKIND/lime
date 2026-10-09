import Foundation
import Network

/// Automatic download choices (Settings → Storage).
enum AutoDownload: String, CaseIterable, Identifiable, Sendable {
    case wifiAndMobile, wifiOnly, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wifiAndMobile: "Wi-Fi and mobile data"
        case .wifiOnly: "Wi-Fi only"
        case .never: "Never"
        }
    }
}

/// How long to keep received media on this phone ("Keep media").
enum KeepMedia: String, CaseIterable, Identifiable, Sendable {
    case forever, year, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .forever: "Forever"
        case .year: "1 year"
        case .month: "30 days"
        }
    }
    /// Files of messages older than this many days are removed; `nil` keeps everything.
    var days: UInt32? {
        switch self {
        case .forever: nil
        case .year: 365
        case .month: 30
        }
    }
}

/// The settings, kept on this phone.
enum MediaSettings {
    static let photosKey = "lime.autoDownload.photos"
    static let videoFilesKey = "lime.autoDownload.videoFiles"
    static let keepKey = "lime.keepMedia"

    static var photos: AutoDownload { AutoDownload(rawValue: UserDefaults.standard.string(forKey: photosKey) ?? "") ?? .wifiAndMobile }
    static var videoFiles: AutoDownload { AutoDownload(rawValue: UserDefaults.standard.string(forKey: videoFilesKey) ?? "") ?? .wifiOnly }
    static var keep: KeepMedia { KeepMedia(rawValue: UserDefaults.standard.string(forKey: keepKey) ?? "") ?? .forever }
}

/// Free space and the kind of network, read when a download is about to start. Tests inject both with launch arguments
/// (`-lime-free-bytes 100000000`, `-lime-network cellular`).
@MainActor
final class StorageGuard {
    static let shared = StorageGuard()

    private let monitor = NWPathMonitor()
    private var onWiFi = true
    private var freeOverride: UInt64?
    private var networkOverride: Bool?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = !path.isExpensive && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) || !path.usesInterfaceType(.cellular))
            Task { @MainActor in self?.onWiFi = wifi }
        }
        monitor.start(queue: DispatchQueue(label: "lime.network"))
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let at = args.firstIndex(of: "-lime-free-bytes"), args.indices.contains(at + 1) { freeOverride = UInt64(args[at + 1]) }
        if let at = args.firstIndex(of: "-lime-network"), args.indices.contains(at + 1) { networkOverride = args[at + 1] != "cellular" }
        #endif
    }

    var isOnWiFi: Bool { networkOverride ?? onWiFi }

    /// Bytes free for important data (what the system would let Lime write before it has to clear space).
    var freeBytes: UInt64 {
        if let freeOverride { return freeOverride }
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let free = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, free > 0 {
            return UInt64(free)
        }
        return UInt64.max
    }

    /// So few bytes are free that automatic downloads pause.
    var isLow: Bool { storageIsLow(freeBytes: freeBytes) }

    /// Room for a file of this size, leaving the phone usable.
    func allows(_ bytes: Int64) -> Bool { storageAllows(freeBytes: freeBytes, neededBytes: UInt64(max(bytes, 0))) }

    /// May Lime fetch this by itself? (Voice always, within the low-storage rule; pictures and the rest by the settings.)
    func mayAutoDownload(_ item: AttachmentItem) -> Bool {
        if isLow { return false }
        let setting: AutoDownload
        switch item.kind {
        case .audio: return true
        case .image: setting = MediaSettings.photos
        case .video, .file: setting = MediaSettings.videoFiles
        }
        switch setting {
        case .wifiAndMobile: return true
        case .wifiOnly: return isOnWiFi
        case .never: return false
        }
    }
}
