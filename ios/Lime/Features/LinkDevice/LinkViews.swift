import SwiftUI
import UIKit

// MARK: The new device (after signing in, when the account already has a phone)

/// The QR, the code, the progress and the way out, for a device that is linking to the person's phone (LIME-343a).
struct LinkNewDeviceView: View {
    @Environment(AccountSession.self) private var session
    let model: LinkToThisDevice
    let onRetry: () -> Void
    let onClose: () -> Void
    @State private var showingText = false

    var body: some View {
        Group {
            switch model.phase {
            case .waiting: waiting
            case .compare(let code):
                MoveCodeStep(code: code, onMatch: { model.matches() }, onMismatch: { model.cancel(); onClose() })
            case .receiving(let step):
                MoveProgressStep(title: step == .package ? "Getting your chats" : "Getting the last 45 days", info: model.progress, onCancel: { model.cancel(); onClose() })
            case .done:
                done
            case .failed(let failure):
                LinkFailureStep(failure: failure, retryTitle: "Try again", onRetry: onRetry, onClose: onClose)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            if model.historyMissing {
                Text("Couldn't get the last 45 days").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                Text("lime works. New messages arrive as usual.").font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                PrimaryButton(title: "Continue", identifier: "link-continue") { Task { await session.moveArrived() } }
            } else {
                ProgressView()
                Text("Opening lime…").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("link-opening")
            }
        }
        .task { if !model.historyMissing { await session.moveArrived() } }
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            Text("Scan this with your phone").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            if let image = QRImage.make(model.qr, size: 240) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 240, height: 240).padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Code to scan with your phone")
                    .accessibilityIdentifier("link-qr")
            }
            Text("On your phone: Settings → Linked Devices → Link a device")
                .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            DisclosureGroup("Can't scan? Use the code", isExpanded: $showingText) {
                VStack(spacing: 10) {
                    Text(model.qr).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("link-qr-text")
                    Button("Copy the code") { UIPasteboard.general.string = model.qr; Announce.say("Code copied") }
                        .font(Theme.body).frame(minHeight: 44).accessibilityIdentifier("link-copy")
                }
                .padding(.top, 8)
            }
            .font(Theme.body).tint(Theme.text)
            ProgressView().controlSize(.small).accessibilityLabel("Waiting for your phone")
        }
    }
}

struct LinkFailureStep: View {
    let failure: LinkFailure
    let retryTitle: String
    let onRetry: () -> Void
    let onClose: () -> Void

    private var title: String {
        switch failure {
        case .cantConnect: "Couldn't connect"
        case .dropped: "The connection stopped"
        case .stoppedByOther: "The link was stopped"
        case .wrongCode: "That code isn't right"
        case .tooManyDevices: "This account has 5 devices"
        case .failed: "Something went wrong"
        }
    }

    private var detail: String {
        switch failure {
        case .cantConnect: "Turn on Personal Hotspot on one device, or move them closer, then try again."
        case .dropped, .failed: "Nothing was linked. Start again."
        case .stoppedByOther: "Nothing was linked."
        case .wrongCode: "Use the code on the new device, for this account."
        case .tooManyDevices: "On your phone, unlink one in Settings → Linked Devices. Then try again."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            Text(title).font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text(detail).font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            PrimaryButton(title: retryTitle, identifier: "link-retry", action: onRetry)
            Button("Close", action: onClose).font(Theme.body).frame(minHeight: 44).accessibilityIdentifier("link-close")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-failed")
        .onAppear { UIAccessibility.post(notification: .announcement, argument: title) }
    }
}

// MARK: The phone (Settings → Linked Devices)

/// What the list does for each device (LIME-343a): kept apart so it can be tested.
enum LinkedDevicesRules {
    static let limit = 5
    static func canLinkMore(count: Int) -> Bool { count < limit }
    /// Only a computer can be unlinked from here: a phone or tablet holds the master secret (DESIGN-M2 will change that).
    static func canUnlink(_ device: MyDevice) -> Bool { !device.isThisDevice && device.kind == "computer" }
    static func kindWords(_ kind: String) -> String {
        switch kind {
        case "phone": "Phone"
        case "tablet": "Tablet"
        case "computer": "Computer"
        default: "Device"
        }
    }
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "phone": "iphone"
        case "tablet": "ipad"
        case "computer": "laptopcomputer"
        default: "questionmark.square.dashed"
        }
    }
    static func title(_ device: MyDevice) -> String {
        if !device.name.isEmpty { return device.name }
        return device.isThisDevice ? "This device" : "\(kindWords(device.kind)) (no name yet)"
    }
}

struct LinkedDevicesScreen: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @State private var devices: [MyDevice] = []
    @State private var loaded = false
    @State private var model: LinkFromPhone?
    @State private var scanning = false
    @State private var typing = false
    @State private var typed = ""
    @State private var problem: LinkFailure?
    @State private var confirming: MyDevice?
    @State private var unlinkFailed = false

    var body: some View {
        SettingsPage(title: "Linked Devices") {
            if let model {
                LinkPhoneFlow(model: model, onRetry: { reset() }, onClose: { reset(); Task { await load() } }).padding(.top, 12)
            } else {
                list
                add
            }
        }
        .task { await load() }
        .onDisappear { model?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .fullScreenCover(isPresented: $scanning) {
            VStack(spacing: 0) {
                SheetHeader(title: "Scan the code", leading: .close { scanning = false })
                CameraScanner { text in scanning = false; begin(with: text) }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).padding(.horizontal, 16)
                    .accessibilityIdentifier("link-scan-camera")
                Text("Point your camera at the code on the new device.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(16)
            }
            .limeBackground()
        }
        .confirmationDialog("Unlink \(confirming.map { LinkedDevicesRules.title($0) } ?? "")?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button("Unlink", role: .destructive) { if let device = confirming { Task { await unlink(device) } } }
                .accessibilityIdentifier("device-unlink-confirm")
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("It stops getting your lime messages. You'll confirm with \(SystemLockAuthenticator.methodName).")
        }
    }

    private var list: some View {
        VStack(spacing: 12) {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.deviceId) { index, device in
                        row(device).overlay(alignment: .bottom) { if index < devices.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) } }
                    }
                    if devices.isEmpty && loaded {
                        Text("This device").font(Theme.title).foregroundStyle(Theme.text).padding(18).accessibilityIdentifier("devices-this")
                    }
                }
            }
            if unlinkFailed {
                Text("Couldn't unlink. Check your connection and try again.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("devices-unlink-failed")
            }
        }
    }

    private func row(_ device: MyDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: LinkedDevicesRules.symbol(device.kind)).font(.system(size: 24)).frame(width: 32).foregroundStyle(Theme.text).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LinkedDevicesRules.title(device)).font(Theme.title).foregroundStyle(Theme.text)
                    .accessibilityIdentifier(device.isThisDevice ? "devices-this" : "device-name-\(device.deviceId)")
                Text(device.isThisDevice ? "This device · Active now" : "\(LinkedDevicesRules.kindWords(device.kind)) · Added \(KeysScreen.date(device.addedAt))")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if LinkedDevicesRules.canUnlink(device) {
                Button("Unlink") { confirming = device }
                    .font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Unlink \(LinkedDevicesRules.title(device))")
                    .accessibilityIdentifier("device-unlink-\(device.deviceId)")
            } else if !device.isThisDevice {
                Text("Unlink from that device").font(Theme.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                    .accessibilityIdentifier("device-unlink-elsewhere-\(device.deviceId)")
            }
        }
        .padding(18).modifier(OneStopRow())
    }

    @ViewBuilder private var add: some View {
        if LinkedDevicesRules.canLinkMore(count: devices.count) {
            SettingsCard {
                VStack(spacing: 12) {
                    Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 34)).foregroundStyle(Theme.text).accessibilityHidden(true)
                    Text("On the new device, sign in to lime and choose Link to your phone.").font(Theme.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    PrimaryButton(title: "Link a device", identifier: "link-a-device") { scanning = true }
                    Button("Enter the code") { typing.toggle() }
                        .font(Theme.body).foregroundStyle(Theme.text).frame(minHeight: 44).accessibilityIdentifier("link-enter")
                    if typing {
                        TextField("Paste or type the code", text: $typed)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("link-code-field")
                        HStack {
                            PasteButton(payloadType: String.self) { strings in typed = strings.first ?? typed }
                            Spacer()
                            Button("Continue") { begin(with: typed) }
                                .font(Theme.font(.body, weight: .semibold)).frame(minHeight: 44)
                                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("link-continue-code")
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity)
            }
            if let problem { LinkFailureStep(failure: problem, retryTitle: "Try again", onRetry: { self.problem = nil }, onClose: { self.problem = nil }) }
            SettingsFootnote(text: "A computer you unlink stops getting your messages.")
                .accessibilityIdentifier("devices-note")
        } else {
            SettingsCard {
                VStack(spacing: 8) {
                    Text("5 of 5 devices").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Text("Unlink one first.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
                .padding(18).frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("devices-full")
            }
        }
    }

    private func load() async {
        devices = await store.loadMyDevices()
        loaded = true
    }

    private func begin(with text: String) {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        problem = nil
        do {
            let made = try LinkFactory.phone(store: store, qr: code)
            model = made
            made.start()
            UIApplication.shared.isIdleTimerDisabled = true
        } catch StoreError.MasterKeyNotOnDevice {
            problem = .failed
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

    private func unlink(_ device: MyDevice) async {
        confirming = nil
        guard await AppLock.shared.authenticator.authenticate(reason: "Unlink \(LinkedDevicesRules.title(device))") else { return }
        unlinkFailed = !(await store.unlinkDevice(device.deviceId))
        await load()
    }
}

private struct LinkPhoneFlow: View {
    let model: LinkFromPhone
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        switch model.phase {
        case .connecting:
            VStack(spacing: 14) {
                ProgressView()
                Text("Looking for the new device…").font(Theme.body).foregroundStyle(Theme.textSecondary).announcesWhenShown("Looking for the new device")
                Button("Cancel", role: .cancel) { model.cancel(); onClose() }.frame(minHeight: 44).accessibilityIdentifier("link-cancel")
            }
            .accessibilityIdentifier("link-connecting")
        case .compare(let code):
            VStack(spacing: 12) {
                MoveCodeStep(code: code, onMatch: { model.matches() }, onMismatch: { model.cancel(); onClose() })
                if model.notYou {
                    Text("Couldn't confirm it's you. Try again.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("link-not-you")
                } else {
                    Text("You'll confirm with \(SystemLockAuthenticator.methodName).").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                }
            }
        case .waitingForOther:
            VStack(spacing: 14) {
                ProgressView()
                Text("Waiting for the new device…").font(Theme.body).foregroundStyle(Theme.textSecondary).announcesWhenShown("Waiting for the new device")
                Button("Cancel", role: .cancel) { model.cancel(); onClose() }.frame(minHeight: 44).accessibilityIdentifier("link-cancel")
            }
        case .sending(let step):
            MoveProgressStep(title: step == .package ? "Sending your chats" : "Sending the last 45 days", info: model.progress, onCancel: { model.cancel(); onClose() })
        case .done:
            VStack(spacing: 12) {
                Text("Device linked").font(Theme.font(.title2, weight: .semibold)).foregroundStyle(Theme.text).announcesWhenShown("Device linked")
                if model.historyMissing { Text("The last 45 days didn't go. It works without them.").font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center) }
                PrimaryButton(title: "Done", identifier: "link-done", action: onClose)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("link-linked")
        case .failed(let failure):
            LinkFailureStep(failure: failure, retryTitle: "Try again", onRetry: onRetry, onClose: onClose)
        }
    }
}
