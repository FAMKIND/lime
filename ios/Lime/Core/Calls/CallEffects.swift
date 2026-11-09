import AVFoundation
import SwiftUI

/// The camera reactions Apple draws into the video (LIME-280). Apple draws them into the picture that is sent, so the other person cannot turn them off and lime cannot
/// cap their flashing: Fireworks and Lasers (the two that flash) are not offered, and none are while this phone's Reduce Motion is on (LIME-130-4c, DESIGN-34).
/// Each is played by the system on this phone before the picture is encrypted and sent.
enum CallReaction: String, CaseIterable, Identifiable {
    case hearts, thumbsUp, thumbsDown, balloons, confetti, rain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hearts: "Hearts"
        case .thumbsUp: "Thumbs up"
        case .thumbsDown: "Thumbs down"
        case .balloons: "Balloons"
        case .confetti: "Confetti"
        case .rain: "Rain"
        }
    }

    var symbol: String {
        switch self {
        case .hearts: "heart.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .thumbsDown: "hand.thumbsdown.fill"
        case .balloons: "balloon.fill"
        case .confetti: "party.popper.fill"
        case .rain: "cloud.rain.fill"
        }
    }

    var type: AVCaptureReactionType {
        switch self {
        case .hearts: .heart
        case .thumbsUp: .thumbsUp
        case .thumbsDown: .thumbsDown
        case .balloons: .balloons
        case .confetti: .confetti
        case .rain: .rain
        }
    }
}

/// What the Effects menu offers right now: the reactions this camera can play, and Apple's Video Effects panel.
struct EffectsSupport: Equatable {
    var reactions: [CallReaction] = []
    var videoEffectsPanel = false
    var isEmpty: Bool { reactions.isEmpty && !videoEffectsPanel }
    static let none = EffectsSupport()
}

enum CallEffects {
    /// The menu's items from what the camera says: reactions only when it can play them (iOS turns them on for apps with the voice-over-IP mode, and the
    /// active format has to support them) and only the ones it lists; the Video Effects panel whenever the camera is on. Nothing when the camera is off.
    static func support(canReact: Bool, available: Set<AVCaptureReactionType>, cameraOn: Bool, reduceMotion: Bool = false) -> EffectsSupport {
        guard cameraOn else { return .none }
        let reactions = canReact && !reduceMotion ? CallReaction.allCases.filter { available.contains($0.type) } : []
        return EffectsSupport(reactions: reactions, videoEffectsPanel: true)
    }

    /// The menu looks again every second (`CallEffectsButton`), so turning Reduce Motion on or off during a call changes it within a second.
    @MainActor static func support(for device: AVCaptureDevice?, cameraOn: Bool, reduceMotion: Bool? = nil) -> EffectsSupport {
        let reduceMotion = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-effects") { return cameraOn ? EffectsSupport(reactions: reduceMotion ? [] : CallReaction.allCases, videoEffectsPanel: true) : .none }
        #endif
        guard let device else { return .none }
        return support(canReact: device.canPerformReactionEffects, available: device.availableReactionTypes, cameraOn: cameraOn, reduceMotion: reduceMotion)
    }

    static func perform(_ reaction: CallReaction, on device: AVCaptureDevice?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-effects") { return }
        #endif
        device?.performEffect(for: reaction.type)
    }

    /// Apple's own panel: background blur (Portrait), Studio Light, and Center Stage where the camera has it.
    static func openVideoEffects() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-effects") { return }
        #endif
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }
}

/// The Effects button of a video call: a menu of Reactions and Video effects, hidden while the camera cannot do either. The camera shows up a moment after the
/// call starts, so it looks again once a second.
struct CallEffectsButton: View {
    let size: CGFloat
    let id: String
    let support: () -> EffectsSupport
    let perform: (CallReaction) -> Void
    @State private var current = EffectsSupport.none

    var body: some View {
        // A ZStack, not a Group: a Group with nothing in it drops the .task below.
        ZStack {
            if !current.isEmpty {
                Menu {
                    if !current.reactions.isEmpty {
                        Section("Reactions") {
                            ForEach(current.reactions) { reaction in
                                Button { perform(reaction) } label: { Label(reaction.title, systemImage: reaction.symbol) }
                                    .accessibilityIdentifier("\(id)-\(reaction.rawValue)")
                            }
                        }
                    }
                    if current.videoEffectsPanel {
                        Button { CallEffects.openVideoEffects() } label: { Label("Video effects\u{2026}", systemImage: "person.crop.rectangle") }
                            .accessibilityIdentifier("\(id)-video-effects")
                    }
                } label: {
                    Image(systemName: "sparkles").font(.system(size: size * 0.4)).foregroundStyle(.white)
                        .frame(width: size, height: size).callRoundBackground()
                }
                .accessibilityLabel("Effects").accessibilityHint("Reactions and video effects")
                .accessibilityIdentifier(id)
            }
        }
        .task {
            while !Task.isCancelled {
                let now = support()
                if now != current { current = now }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
