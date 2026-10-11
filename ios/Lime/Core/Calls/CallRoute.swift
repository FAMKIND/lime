import AVFoundation
import Foundation
import Observation

/// Where the call's sound is going (earpiece, speaker, AirPods…): shown on the call screen, a 2 s toast when it changes mid-call,
/// and logged by port type only (never a device name).
@MainActor
@Observable
final class CallRoute {
    private(set) var name = "iPhone"
    private(set) var symbol = "iphone"
    private(set) var toast: String?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored var onHeadphonesGone: (() -> Void)?

    init() { refresh(announce: false) }

    func start() {
        guard observer == nil else { return }
        refresh(announce: false)
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            Task { @MainActor in self?.changed(reason: AVAudioSession.RouteChangeReason(rawValue: raw)) }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        toastTask?.cancel()
        toast = nil
    }

    private func changed(reason: AVAudioSession.RouteChangeReason?) {
        let before = name
        refresh(announce: false)
        CallDiagnostics.shared.log("audio route change (\(Self.describe(reason))): output \(Self.portKind(AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType))")
        if reason == .oldDeviceUnavailable { onHeadphonesGone?() }
        guard name != before else { return }
        toast = "Audio now on \(name)"
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    private func refresh(announce: Bool) {
        let port = AVAudioSession.sharedInstance().currentRoute.outputs.first
        switch port?.portType {
        case .builtInSpeaker: (name, symbol) = ("Speaker", "speaker.wave.2.fill")
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: (name, symbol) = (port?.portName ?? "Bluetooth", "airpodspro")
        case .headphones, .headsetMic: (name, symbol) = ("Headphones", "headphones")
        default: (name, symbol) = ("iPhone", "iphone")
        }
    }

    /// The kind of port, never its name.
    nonisolated static func portKind(_ type: AVAudioSession.Port?) -> String {
        switch type {
        case .builtInReceiver: "receiver"
        case .builtInSpeaker: "speaker"
        case .bluetoothA2DP: "bluetooth A2DP"
        case .bluetoothHFP: "bluetooth HFP"
        case .bluetoothLE: "bluetooth LE"
        case .headphones: "headphones"
        case .headsetMic: "headset"
        case .some(let other): other.rawValue
        case .none: "none"
        }
    }

    nonisolated static func describe(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: "new device"
        case .oldDeviceUnavailable: "device gone"
        case .categoryChange: "category change"
        case .override: "override"
        case .routeConfigurationChange: "configuration"
        case .wakeFromSleep: "wake"
        case .noSuitableRouteForCategory: "no route"
        default: "other"
        }
    }
}
