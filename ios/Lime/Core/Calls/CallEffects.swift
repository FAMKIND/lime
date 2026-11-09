import AVFoundation
import SwiftUI

/// The camera reactions Apple draws into the video (LIME-280). Each is played by the system on this phone before the picture is encrypted and sent.
enum CallReaction: String, CaseIterable, Identifiable {
    case hearts, thumbsUp, thumbsDown, balloons, confetti, fireworks, rain, lasers
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hearts: "Hearts"
        case .thumbsUp: "Thumbs up"
        case .thumbsDown: "Thumbs down"
        case .balloons: "Balloons"
        case .confetti: "Confetti"
        case .fireworks: "Fireworks"
        case .rain: "Rain"
        case .lasers: "Lasers"
        }
    }

    var symbol: String {
        switch self {
        case .hearts: "heart.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        case .thumbsDown: "hand.thumbsdown.fill"
        case .balloons: "balloon.fill"
        case .confetti: "party.popper.fill"
        case .fireworks: "sparkles"
        case .rain: "cloud.rain.fill"
        case .lasers: "wand.and.rays"
        }
    }

    var type: AVCaptureReactionType {
        switch self {
        case .hearts: .heart
        case .thumbsUp: .thumbsUp
        case .thumbsDown: .thumbsDown
        case .balloons: .balloons
        case .confetti: .confetti
        case .fireworks: .fireworks
        case .rain: .rain
        case .lasers: .lasers
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
    static func support(canReact: Bool, available: Set<AVCaptureReactionType>, cameraOn: Bool) -> EffectsSupport {
        guard cameraOn else { return .none }
        let reactions = canReact ? CallReaction.allCases.filter { available.contains($0.type) } : []
        return EffectsSupport(reactions: reactions, videoEffectsPanel: true)
    }

    static func support(for device: AVCaptureDevice?, cameraOn: Bool) -> EffectsSupport {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-effects") { return cameraOn ? EffectsSupport(reactions: CallReaction.allCases, videoEffectsPanel: true) : .none }
        #endif
        guard let device else { return .none }
        return support(canReact: device.canPerformReactionEffects, available: device.availableReactionTypes, cameraOn: cameraOn)
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
