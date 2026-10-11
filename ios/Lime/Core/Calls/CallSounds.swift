import AVFoundation
import UIKit

/// The call's own sounds (LIME-118): the ringback while "Calling…", a blip when the media comes up, a tone when it ends.
@MainActor
protocol CallSounds: AnyObject {
    func startRingback(video: Bool)
    func stopRingback()
    func playConnect()
    func playEnd()
}

/// Silent stand-in (tests, demo mode).
@MainActor
final class QuietCallSounds: CallSounds {
    func startRingback(video: Bool) {}
    func stopRingback() {}
    func playConnect() {}
    func playEnd() {}
}

/// Plays the bundled tones (`ios/tools/make-call-tones.py` makes them) through the call's audio session: it is play-and-record, so
/// the silent switch does not mute it, and the sound comes from the earpiece for a voice call and the speaker for a video call.
@MainActor
final class SystemCallSounds: CallSounds {
    private var ringback: AVAudioPlayer?
    private var oneShot: AVAudioPlayer?

    private func player(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
            CallDiagnostics.shared.log("sound missing: \(name)")
            return nil
        }
        return try? AVAudioPlayer(contentsOf: url)
    }

    func startRingback(video: Bool) {
        guard ringback == nil, let player = player("lime-ringback") else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: video ? .videoChat : .voiceChat, options: video ? [.allowBluetoothHFP, .defaultToSpeaker] : [.allowBluetoothHFP])
        try? session.setActive(true)
        player.numberOfLoops = -1
        player.volume = 0.6
        player.play()
        ringback = player
        CallDiagnostics.shared.log("ringback started")
    }

    func stopRingback() {
        guard let ringback else { return }
        ringback.stop()
        self.ringback = nil
        CallDiagnostics.shared.log("ringback stopped")
    }

    func playConnect() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        play("lime-connect")
    }

    func playEnd() { play("lime-end") }

    private func play(_ name: String) {
        guard let player = player(name) else { return }
        player.volume = 0.6
        player.play()
        oneShot = player
    }
}
