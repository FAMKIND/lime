import AVFoundation
import SwiftUI

// MARK: My QR code

/// My QR code: my invite link plus my identity-key fingerprint. A teacher who scans it can message me and
/// knows the key is really mine.
struct MyQRScreen: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @State private var info: KeyInfo?
    @State private var loaded = false

    private var username: String? { session.profile?.username }

    var body: some View {
        SettingsPage(title: "My QR Code") {
            if let username, let info {
                let payload = QRPayload(username: username, fingerprint: info.fingerprint)
                SettingsCard {
                    VStack(spacing: 14) {
                        if let image = QRImage.make(payload.text) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 240, height: 240).padding(14)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityLabel("Your QR code").accessibilityIdentifier("my-qr-image")
                        }
                        Text(session.profile?.displayName ?? "").font(Theme.title).foregroundStyle(Theme.text)
                        Text("@\(username)").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("my-qr-username")
                        Text(info.fingerprint).font(.system(.footnote, design: .monospaced, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("my-qr-fingerprint")
                    }
                    .frame(maxWidth: .infinity).padding(20)
                }
                SettingsFootnote(text: "Show this to a teacher you're with. When they scan it with Lime, they can message you and know it's really you. It holds your invite link and your key's fingerprint, nothing else.")
            } else if loaded {
                Text(username == nil ? "Choose a username in Profile to get your QR code."
                                     : "This iPhone has no keys yet. They are made when you sign in.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .padding(.top, 40).padding(.horizontal, 24)
                    .accessibilityIdentifier("my-qr-unavailable")
            }
        }
        .task { info = await store.keyInfo(); loaded = true }
    }
}

// MARK: Scanning

/// What scanning a code found.
@MainActor
@Observable
final class QRScanModel {
    enum State: Equatable {
        case scanning
        case checking
        case notLime
        case nobody
        case itsYou
        case problem(String)
        case found(FoundUser, ScanVerdict)
    }

    private(set) var state: State = .scanning
    private var handling = false

    func restart() { state = .scanning; handling = false }

    /// A string read by the camera (or pasted in a Debug build). Ignores anything while one is being checked.
    func handle(_ text: String, store: ConversationStore) async {
        guard !handling else { return }
        handling = true
        guard let payload = QRPayload.decode(text) else { state = .notLime; return }
        state = .checking
        do {
            guard let person = try await store.find(payload.username) else { state = .nobody; return }
            if person.isSelf { state = .itsYou; return }
            guard let fingerprint = payload.fingerprint else { state = .found(person, .unchecked); return }
            let verdict = try await store.verifyInPerson(userId: person.userId, fingerprint: fingerprint)
            state = .found(person, verdict)
        } catch {
            let problem = ConnectionProblem.from(error)
            store.report(problem)
            state = .problem(problem.message)
        }
    }
}

/// Scan QR Code: point the camera at a teacher's code.
struct ScanQRScreen: View {
    let closeSheet: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model = QRScanModel()
    #if DEBUG
    @State private var pasted = ""
    #endif

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Scan QR Code", leading: .back { dismiss() })
            switch model.state {
            case .scanning:
                CameraScanner { text in Task { await model.handle(text, store: store) } }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("scan-camera")
                Text("Point your camera at a teacher's Lime QR code.")
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(16)
                #if DEBUG
                TextField("Paste a code (Debug)", text: $pasted)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("scan-paste")
                    .onSubmit { Task { await model.handle(pasted, store: store) } }
                #endif
            case .checking:
                ProgressView("Checking…").padding(.top, 60)
            case .notLime:
                message("That isn't a Lime QR code.", id: "scan-not-lime")
            case .nobody:
                message("No teacher found for that code. They may have changed their username or hidden themselves from search.", id: "scan-nobody")
            case .itsYou:
                message("That's your own code. Ask another teacher to show theirs.", id: "scan-self")
            case .problem(let text):
                message(text, id: "scan-problem")
            case .found(let person, let verdict):
                ScanResult(person: person, verdict: verdict, closeSheet: closeSheet)
            }
            Spacer(minLength: 0)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        #if DEBUG
        .task { if let code = store.demoScanCode { await model.handle(code, store: store) } }
        #endif
    }

    private func message(_ text: String, id: String) -> some View {
        VStack(spacing: 16) {
            Text(text).font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .accessibilityIdentifier(id)
            Button("Scan again") { model.restart() }.font(Theme.title).accessibilityIdentifier("scan-again")
        }
        .padding(.top, 50).padding(.horizontal, 28)
    }
}

/// The person a code belongs to, whether the code matched their key, and a Message button.
struct ScanResult: View {
    let person: FoundUser
    let verdict: ScanVerdict
    let closeSheet: () -> Void
    @Environment(ConversationStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            AvatarView(person: Person(id: person.userId, name: person.displayName), size: 88).padding(.top, 24)
            Text(person.displayName).font(Theme.title).foregroundStyle(Theme.text).accessibilityIdentifier("scan-result-name")
            if let detail = NewMessageSheet.detail(person) {
                Text(detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            banner
            Button {
                Task { await store.startChat(with: person); closeSheet() }
            } label: {
                Text("Message").font(Theme.title).foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity).frame(minHeight: 52).background(Theme.accent, in: Capsule())
            }
            .padding(.horizontal, 16).padding(.top, 6)
            .accessibilityIdentifier("scan-message")
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch verdict {
        case .verified:
            Label("Verified in person", systemImage: "checkmark.seal.fill")
                .font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.surface, in: Capsule())
                .accessibilityIdentifier("scan-verified")
        case .mismatch:
            warning("This code doesn't match \(person.displayName)'s key. It may be old, or it may not be theirs. Don't treat them as verified, and ask them to show the code again.",
                    id: "scan-mismatch")
        case .keyChanged:
            warning("The code matches, but \(person.displayName)'s key is different from the one you had (they may have a new phone). Accept the change in the chat first, then scan again.",
                    id: "scan-key-changed")
        case .unchecked:
            Text("This link has no key to check, so \(person.displayName) isn't marked verified.")
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 28)
                .accessibilityIdentifier("scan-unchecked")
        }
    }

    private func warning(_ text: String, id: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Theme.secondary).foregroundStyle(Color.red).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityIdentifier(id)
    }
}

// MARK: The camera

/// The camera's live view that reports the first QR code it reads.
struct CameraScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private nonisolated(unsafe) let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private let note = UILabel()
    private var reported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        note.textColor = .white
        note.numberOfLines = 0
        note.textAlignment = .center
        note.font = .preferredFont(forTextStyle: .body)
        note.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(note)
        NSLayoutConstraint.activate([
            note.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            note.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            note.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.start() : self.say("Camera access is off. Turn it on for Lime in Settings to scan a code.") }
            }
        default: say("Camera access is off. Turn it on for Lime in Settings to scan a code.")
        }
    }

    private func say(_ text: String) { note.text = text }

    private func start() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            say("This device has no camera to scan with.")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !reported, let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        reported = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        session.stopRunning()
        onCode?(text)
    }
}
