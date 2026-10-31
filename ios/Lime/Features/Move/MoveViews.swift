import SwiftUI
import UIKit

// MARK: Shared steps

/// The 6 digits both phones show. The person compares them and says whether they match.
private struct MoveCodeStep: View {
    let code: String
    let onMatch: () -> Void
    let onMismatch: () -> Void

    private var spaced: String { code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code }

    var body: some View {
        VStack(spacing: 20) {
            Text("Do the codes match?").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Look at the other phone.").font(Theme.body).foregroundStyle(Theme.textSecondary)
            Text(spaced)
                .font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.text).minimumScaleFactor(0.6).lineLimit(1)
                .padding(.vertical, 18).frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                // Read as single digits, not "four hundred eighty-two thousand…".
                .accessibilityLabel("Check code, " + code.map(String.init).joined(separator: " "))
                .accessibilityIdentifier("move-code")
            PrimaryButton(title: "They match", identifier: "move-match", action: onMatch)
            Button("They don't match", role: .destructive, action: onMismatch)
                .font(Theme.body).frame(minHeight: 44)
                .accessibilityIdentifier("move-nomatch")
        }
    }
}

/// Bytes, items, a time estimate; announced to VoiceOver every tenth.
private struct MoveProgressStep: View {
    let title: String
    let info: MoveProgressInfo
    let onCancel: () -> Void
    @State private var announced = -1

    var body: some View {
        VStack(spacing: 18) {
            Text(title).font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            ProgressView(value: info.fraction).tint(Theme.text)
                .accessibilityLabel("Progress").accessibilityValue(info.spoken)
                .accessibilityIdentifier("move-progress")
            if info.total > 0 {
                Text(info.megabytes).font(Theme.body).foregroundStyle(Theme.text).accessibilityIdentifier("move-bytes")
            }
            if info.messages + info.attachments > 0 {
                Text("\(info.conversations) chats · \(info.messages) messages · \(info.attachments) files")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            if let left = info.timeLeft { Text(left).font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
            Text("Keep both phones nearby and lime open.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel, action: onCancel).font(Theme.body).frame(minHeight: 44)
                .accessibilityIdentifier("move-cancel")
        }
        .onChange(of: Int(info.fraction * 10)) { _, tenth in
            guard tenth != announced, tenth > 0 else { return }
            announced = tenth
            UIAccessibility.post(notification: .announcement, argument: info.spoken)
        }
    }
}

private struct MoveFailureStep: View {
    let failure: MoveFailure
    let retryTitle: String
    let onRetry: () -> Void
    let onClose: () -> Void

    private var title: String {
        switch failure {
        case .cantConnect: "Couldn't connect"
        case .dropped: "The connection stopped"
        case .stoppedByOther: "The move was stopped"
        case .wrongCode: "That code isn't right"
        case .noConfirmation: "No answer from your new phone"
        case .failed: "Something went wrong"
        }
    }

    private var detail: String {
        switch failure {
        case .cantConnect: "Turn on Personal Hotspot on one phone, or move the phones closer, then try again."
        case .dropped: "Nothing changed on your old phone. Start again."
        case .stoppedByOther: "Nothing changed on your old phone."
        case .wrongCode: "Use the code on your new phone, for this account."
        case .noConfirmation: "If lime opened there with your chats, sign out here. If not, try again."
        case .failed: "Nothing changed on your old phone. Try again."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            Text(title).font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text(detail).font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            PrimaryButton(title: retryTitle, identifier: "move-retry", action: onRetry)
            Button("Close", action: onClose).font(Theme.body).frame(minHeight: 44).accessibilityIdentifier("move-close")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("move-failed")
        .onAppear { UIAccessibility.post(notification: .announcement, argument: title) }
    }
}

// MARK: The new phone

/// Right after signing in, when the account already has a phone: bring everything here, or start with new keys.
struct MoveOfferView: View {
    @Environment(AccountSession.self) private var session
    @State private var model: MoveToNewPhone?
    @State private var failedToStart = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { Task { await session.cancelPendingMove() } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18)).foregroundStyle(Theme.text)
                        .frame(width: 48, height: 48).limeGlass()
                }
                .accessibilityLabel("Back").accessibilityIdentifier("move-offer-back")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8)

            ScrollView {
                VStack(spacing: 22) {
                    if let model {
                        MoveNewPhoneView(model: model, onRetry: { begin() }, onClose: { close() })
                    } else {
                        offer
                    }
                }
                .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 32)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var offer: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 44)).foregroundStyle(Theme.text).accessibilityHidden(true)
            Text("Move from your old phone?").font(Theme.font(.title, weight: .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text("Bring your chats, files and keys here.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Transfer", identifier: "move-transfer") { begin() }
            if failedToStart {
                Text("Couldn't start. Try again, or start fresh.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Button("Start fresh") { Task { await session.startFresh() } }
                .font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).frame(minHeight: 48)
                .accessibilityIdentifier("move-start-fresh")
            Text("Starting fresh makes new keys. Your contacts will be asked to accept them, and your old chats stay on your old phone.")
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
    }

    private func begin() {
        model?.cancel()
        model = nil
        guard let made = try? MoveFactory.newPhone(userID: session.pendingMoveUserID ?? "") else { failedToStart = true; return }
        failedToStart = false
        model = made
        made.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func close() {
        model?.cancel()
        model = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

/// The QR, the code, the progress and the way out, for the new phone.
struct MoveNewPhoneView: View {
    @Environment(AccountSession.self) private var session
    let model: MoveToNewPhone
    let onRetry: () -> Void
    let onClose: () -> Void
    @State private var showingText = false

    var body: some View {
        Group {
            switch model.phase {
            case .waiting: waiting
            case .compare(let code):
                MoveCodeStep(code: code, onMatch: { model.matches() }, onMismatch: { model.cancel(); onClose() })
            case .receiving, .finishing:
                MoveProgressStep(title: model.phase == .finishing ? "Almost there" : "Moving to this phone", info: model.progress, onCancel: { model.cancel(); onClose() })
            case .done:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Opening lime…").font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
                .task { await session.moveArrived() }
            case .failed(let failure):
                MoveFailureStep(failure: failure, retryTitle: "Try again", onRetry: onRetry, onClose: onClose)
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            Text("Scan this with your old phone").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            if let image = QRImage.make(model.qr, size: 240) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 240, height: 240).padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Code to scan with your old phone")
                    .accessibilityIdentifier("move-qr")
            }
            Text("On your old phone: Settings → Account → Transfer to a new phone")
                .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            DisclosureGroup("Can't scan? Use the code", isExpanded: $showingText) {
                VStack(spacing: 10) {
                    Text(model.qr).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("move-qr-text")
                    Button("Copy the code") { UIPasteboard.general.string = model.qr }
                        .font(Theme.body).frame(minHeight: 44).accessibilityIdentifier("move-copy")
                    Text("On your old phone, choose “Enter the code” and paste or type it.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 8)
            }
            .font(Theme.body).tint(Theme.text)
            .accessibilityIdentifier("move-qr-fallback")
            ProgressView().controlSize(.small).accessibilityLabel("Waiting for your old phone")
        }
    }
}

// MARK: The old phone (Settings → Account → Transfer to a new phone)

struct MoveOldPhoneScreen: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @State private var model: MoveFromOldPhone?
    @State private var scanning = false
    @State private var typing = false
    @State private var typed = ""
    @State private var problem: MoveFailure?

    var body: some View {
        SettingsPage(title: "Transfer to a New Phone") {
            if let model {
                MoveOldPhoneFlow(model: model, onRetry: { reset() }, onClose: { reset() })
                    .padding(.top, 12)
            } else {
                start
            }
        }
        .onDisappear { model?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .fullScreenCover(isPresented: $scanning) {
            VStack(spacing: 0) {
                SheetHeader(title: "Scan the code", leading: .close { scanning = false })
                CameraScanner { text in scanning = false; begin(with: text) }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).padding(.horizontal, 16)
                    .accessibilityIdentifier("move-scan-camera")
                Text("Point your camera at the code on your new phone.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(16)
            }
            .background(Theme.canvas.ignoresSafeArea())
        }
    }

    private var start: some View {
        VStack(spacing: 16) {
            SettingsCard {
                VStack(spacing: 12) {
                    Image(systemName: "iphone.and.arrow.forward").font(.system(size: 40)).foregroundStyle(Theme.text).accessibilityHidden(true)
                    Text("On your new phone, sign in to lime and choose Transfer. Then scan the code it shows.")
                        .font(Theme.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    PrimaryButton(title: "Scan the code", identifier: "move-old-scan") { scanning = true }
                    Button("Enter the code") { typing.toggle() }
                        .font(Theme.body).foregroundStyle(Theme.text).frame(minHeight: 44).accessibilityIdentifier("move-old-enter")
                    if typing {
                        TextField("Paste or type the code", text: $typed)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("move-old-code-field")
                        HStack {
                            PasteButton(payloadType: String.self) { strings in typed = strings.first ?? typed }
                            Spacer()
                            Button("Continue") { begin(with: typed) }
                                .font(Theme.font(.body, weight: .semibold)).frame(minHeight: 44)
                                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("move-old-continue")
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity)
            }
            if let problem {
                MoveFailureStep(failure: problem, retryTitle: "Try again", onRetry: { self.problem = nil }, onClose: { self.problem = nil })
            }
            SettingsFootnote(text: "Everything moves straight between the two phones, over Wi-Fi or a direct link. Nothing goes through lime's servers. When it's done, this phone is signed out and emptied.")
        }
    }

    private func begin(with text: String) {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        problem = nil
        do {
            let made = try MoveFactory.oldPhone(store: store, session: session, qr: code)
            model = made
            made.start()
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            problem = .wrongCode
        }
    }

    private func reset() {
        model?.cancel()
        model = nil
        typed = ""
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

private struct MoveOldPhoneFlow: View {
    let model: MoveFromOldPhone
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        switch model.phase {
        case .connecting:
            VStack(spacing: 14) {
                ProgressView()
                Text("Looking for your new phone…").font(Theme.body).foregroundStyle(Theme.textSecondary)
                Button("Cancel", role: .cancel) { model.cancel(); onClose() }.frame(minHeight: 44).accessibilityIdentifier("move-cancel")
            }
            .accessibilityIdentifier("move-connecting")
        case .compare(let code):
            MoveCodeStep(code: code, onMatch: { model.matches() }, onMismatch: { model.cancel(); onClose() })
        case .waitingForOther:
            VStack(spacing: 14) {
                ProgressView()
                Text("Waiting for your new phone…").font(Theme.body).foregroundStyle(Theme.textSecondary)
                Button("Cancel", role: .cancel) { model.cancel(); onClose() }.frame(minHeight: 44).accessibilityIdentifier("move-cancel")
            }
        case .sending:
            MoveProgressStep(title: "Moving to your new phone", info: model.progress, onCancel: { model.cancel(); onClose() })
        case .done:
            Text("lime moved to your new phone").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                .accessibilityIdentifier("move-done")
        case .failed(let failure):
            MoveFailureStep(failure: failure, retryTitle: "Try again", onRetry: onRetry, onClose: onClose)
        }
    }
}

// MARK: After the move

/// Shown once on the signed-out screen after this phone handed its account over.
struct MovedAwayNotice: View {
    @Environment(AccountSession.self) private var session

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(Theme.text).accessibilityHidden(true)
            Text("lime moved to your new phone").font(Theme.font(.title, weight: .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("moved-notice")
            Text("Your chats, files and keys are there now. This phone is signed out and emptied.")
                .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            PrimaryButton(title: "OK", identifier: "moved-ok") { session.movedAway = false }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear { UIAccessibility.post(notification: .announcement, argument: "lime moved to your new phone") }
    }
}
