import AVFoundation
import CallKit
import Foundation

/// The system's call screen (CallKit): incoming and outgoing calls show in the system UI, and Bluetooth/headset buttons work.
/// A call rings only while Lime is open or recently open, until push (LIME-113+).
@MainActor
final class CallKitSystem: NSObject, CallSystem, CXProviderDelegate {
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMute: ((String, Bool) -> Void)?
    private let provider: CXProvider
    private let controller = CXCallController()

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
        CallDiagnostics.shared.log("callkit provider created")
    }

    /// Debug: reports a fake incoming call, waits 3 s, ends it, and logs each step (About → CallKit self-test).
    func selfTest() async {
        let diag = CallDiagnostics.shared
        let id = UUID(uuidString: "00000000-0000-4000-8000-00000000A11E")!
        diag.log("self-test: start")
        let began = Date()
        reportIncoming(callID: id.uuidString.lowercased(), name: "lime test", video: false) { refusal in
            diag.log("self-test: report completion after \(Int(Date().timeIntervalSince(began) * 1000)) ms, error: \(refusal ?? "none")")
        }
        try? await Task.sleep(for: .seconds(3))
        diag.log("self-test: ending")
        provider.reportCall(with: id, endedAt: nil, reason: .remoteEnded)
        try? await Task.sleep(for: .seconds(1))
        diag.log("self-test: done (a 'report completion' line above means CallKit answered; none means it is silent)")
    }

    private func uuid(_ id: String) -> UUID { UUID(uuidString: id) ?? UUID() }

    func reportIncoming(callID: String, name: String, video: Bool, completion: @escaping @MainActor (String?) -> Void) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: name)
        update.localizedCallerName = name
        update.hasVideo = video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        CallDiagnostics.shared.log("callkit reporting incoming")
        // The completion-handler form, not the async one: on a device the async form was suspected of never resuming (LIME-111-fix3b).
        provider.reportNewIncomingCall(with: uuid(callID), update: update) { error in
            let message = error.map { "\($0)" }
            Task { @MainActor in completion(message) }
        }
    }

    func reportOutgoing(callID: String, name: String, video: Bool) {
        let handle = CXHandle(type: .generic, value: name)
        let action = CXStartCallAction(call: uuid(callID), handle: handle)
        action.isVideo = video
        controller.request(CXTransaction(action: action)) { _ in }
    }

    func reportConnected(callID: String) {
        provider.reportOutgoingCall(with: uuid(callID), connectedAt: nil)
    }

    func reportEnded(callID: String, answeredOrOutgoing: Bool) {
        provider.reportCall(with: uuid(callID), endedAt: nil, reason: answeredOrOutgoing ? .remoteEnded : .unanswered)
    }

    // MARK: CXProviderDelegate

    nonisolated func providerDidBegin(_ provider: CXProvider) {
        Task { @MainActor in CallDiagnostics.shared.log("callkit providerDidBegin") }
    }

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in CallDiagnostics.shared.log("callkit providerDidReset") }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor in CallDiagnostics.shared.log("callkit start action") }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let id = action.callUUID.uuidString.lowercased()
        Task { @MainActor in CallDiagnostics.shared.log("callkit answer"); self.onAnswer?(id) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID.uuidString.lowercased()
        Task { @MainActor in CallDiagnostics.shared.log("callkit end"); self.onEnd?(id) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let id = action.callUUID.uuidString.lowercased()
        let muted = action.isMuted
        Task { @MainActor in CallDiagnostics.shared.log("callkit mute \(muted)"); self.onMute?(id, muted) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in CallDiagnostics.shared.log("callkit audio activated") }
        WebRTCMedia.audioSessionActivated(audioSession)
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in CallDiagnostics.shared.log("callkit audio deactivated") }
        WebRTCMedia.audioSessionDeactivated(audioSession)
    }
}

/// A stand-in for UI tests and previews: no system call screen.
@MainActor
final class QuietCallSystem: CallSystem {
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMute: ((String, Bool) -> Void)?
    func reportIncoming(callID: String, name: String, video: Bool, completion: @escaping @MainActor (String?) -> Void) { completion(nil) }
    func reportOutgoing(callID: String, name: String, video: Bool) {}
    func reportConnected(callID: String) {}
    func reportEnded(callID: String, answeredOrOutgoing: Bool) {}
}
