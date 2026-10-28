import AVFoundation
import SwiftUI

/// The microphones a recording can use (LIME-241): the iPhone's own, AirPods, a wired or USB mic. The choice is remembered (by the input's id) and put back
/// in force when a recording starts.
@MainActor
@Observable
final class MicChoice {
    struct Input: Identifiable, Equatable {
        let id: String
        let name: String
        let symbol: String
    }

    static let key = "lime.podcast.mic"
    private(set) var inputs: [Input] = []
    private(set) var currentID = ""
    private var demo = false

    var current: Input? { inputs.first { $0.id == currentID } ?? inputs.first }

    /// Reads what is connected now. In the demo (no hardware) three made-up inputs stand in.
    func refresh(demo: Bool) {
        self.demo = demo
        let remembered = UserDefaults.standard.string(forKey: Self.key)
        if demo {
            inputs = [Input(id: "builtin", name: "iPhone microphone", symbol: "mic.fill"), Input(id: "airpods", name: "AirPods", symbol: "airpods"), Input(id: "usb", name: "USB microphone", symbol: "cable.connector")]
            currentID = inputs.contains { $0.id == remembered } ? remembered ?? "builtin" : "builtin"
            return
        }
        let session = AVAudioSession.sharedInstance()
        // Bluetooth inputs only show once the session can record with them.
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        inputs = (session.availableInputs ?? []).map { Input(id: $0.uid, name: $0.portName, symbol: Self.symbol($0.portType)) }
        let now = session.currentRoute.inputs.first?.uid ?? inputs.first?.id ?? ""
        currentID = inputs.contains { $0.id == remembered } ? remembered ?? now : now
        apply()
    }

    func choose(_ id: String) {
        guard inputs.contains(where: { $0.id == id }) else { return }
        currentID = id
        UserDefaults.standard.set(id, forKey: Self.key)
        apply()
    }

    /// Puts the chosen input in force (also called when a recording starts).
    func apply() {
        guard !demo, let port = AVAudioSession.sharedInstance().availableInputs?.first(where: { $0.uid == currentID }) else { return }
        try? AVAudioSession.sharedInstance().setPreferredInput(port)
    }

    private static func symbol(_ type: AVAudioSession.Port) -> String {
        switch type {
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: "airpods"
        case .headsetMic: "headphones"
        case .usbAudio: "cable.connector"
        default: "mic.fill"
        }
    }
}
