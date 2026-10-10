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
    }

    private func uuid(_ id: String) -> UUID { UUID(uuidString: id) ?? UUID() }

    func reportIncoming(callID: String, name: String, video: Bool) async -> Bool {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: name)
        update.localizedCallerName = name
        update.hasVideo = video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        do {
            try await provider.reportNewIncomingCall(with: uuid(callID), update: update)
            return true
        } catch {
            return false
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

    nonisolated func providerDidReset(_ provider: CXProvider) {}

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let id = action.callUUID.uuidString.lowercased()
        Task { @MainActor in self.onAnswer?(id) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID.uuidString.lowercased()
        Task { @MainActor in self.onEnd?(id) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let id = action.callUUID.uuidString.lowercased()
        let muted = action.isMuted
        Task { @MainActor in self.onMute?(id, muted) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}
    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}

/// A stand-in for UI tests and previews: no system call screen.
@MainActor
final class QuietCallSystem: CallSystem {
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMute: ((String, Bool) -> Void)?
    func reportIncoming(callID: String, name: String, video: Bool) async -> Bool { true }
    func reportOutgoing(callID: String, name: String, video: Bool) {}
    func reportConnected(callID: String) {}
    func reportEnded(callID: String, answeredOrOutgoing: Bool) {}
}
