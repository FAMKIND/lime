import ContactsUI
import MessageUI
import SwiftUI

// MARK: The people picked in Apple's contact picker

/// What Lime keeps of a picked contact: only where to send the invite. Nothing is stored or uploaded.
struct InviteRecipient: Equatable, Sendable {
    let phones: [String]
    let emails: [String]
}

/// Apple's own contact picker: it runs in a separate process, so Lime needs no Contacts permission and
/// only ever receives the entries the teacher picks.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: ([InviteRecipient]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private nonisolated(unsafe) let onPick: ([InviteRecipient]) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping ([InviteRecipient]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let picked = contacts.map {
                InviteRecipient(phones: $0.phoneNumbers.map { $0.value.stringValue }, emails: $0.emailAddresses.map { $0.value as String })
            }
            onPick(picked)
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) { onCancel() }
    }
}

// MARK: Messages, Mail and the share sheet (all from the teacher's own phone)

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let done: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: () -> Void
        init(_ done: @escaping () -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { done() }
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let done: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients(recipients)
        controller.setSubject("Join me on Lime")
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: () -> Void
        init(_ done: @escaping () -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { done() }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    let done: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in done() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: The invite flow

/// Invite teachers: pick people in Apple's picker, choose Messages, Mail or Share, and the composer opens
/// with the invite text already written. The invite goes from the teacher's own phone; Lime's servers
/// never send it and never learn who was invited.
struct InviteFlow: ViewModifier {
    @Binding var start: Bool
    let username: String?

    private enum Step: Identifiable {
        case picker, messages([String]), mail([String]), share
        var id: String {
            switch self {
            case .picker: "picker"
            case .messages: "messages"
            case .mail: "mail"
            case .share: "share"
            }
        }
    }

    @State private var step: Step?
    @State private var chosen: [InviteRecipient] = []
    @State private var choosing = false

    private var text: String { username.map(InviteLink.message(username:)) ?? InviteLink.generalMessage }
    private var phones: [String] { chosen.compactMap(\.phones.first) }
    private var emails: [String] { chosen.compactMap(\.emails.first) }

    func body(content: Content) -> some View {
        content
            .onChange(of: start) { _, wanted in
                if wanted { step = .picker; start = false }
            }
            .fullScreenCover(item: $step) { step in
                switch step {
                case .picker:
                    ContactPicker(onPick: { picked in
                        chosen = picked
                        self.step = nil
                        // The picker is closing; offer the channels once it has gone.
                        Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); choosing = true }
                    }, onCancel: { self.step = nil })
                    .ignoresSafeArea()
                case .messages(let to):
                    MessageComposer(recipients: to, body: text) { self.step = nil }.ignoresSafeArea()
                case .mail(let to):
                    MailComposer(recipients: to, body: text) { self.step = nil }.ignoresSafeArea()
                case .share:
                    ShareSheet(text: text) { self.step = nil }.ignoresSafeArea()
                }
            }
            .confirmationDialog("Send your invite with", isPresented: $choosing, titleVisibility: .visible) {
                if MFMessageComposeViewController.canSendText() {
                    Button("Messages") { step = .messages(phones) }
                }
                if MFMailComposeViewController.canSendMail() {
                    Button("Mail") { step = .mail(emails) }
                }
                Button("Share…") { step = .share }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It's sent from your own phone. Lime never sees who you invite.")
            }
    }
}

extension View {
    func inviteFlow(start: Binding<Bool>, username: String?) -> some View {
        modifier(InviteFlow(start: start, username: username))
    }
}

/// The "Invite a teacher" card (shown when you have no chats yet) and the "Invite teachers to Lime" row.
struct InviteCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 34)).foregroundStyle(Theme.text)
            Text("Invite a teacher").font(Theme.title).foregroundStyle(Theme.text)
            Text("Bring a colleague to Lime. Pick them from your contacts and send the invite from your own phone.")
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button(action: action) {
                Text("Invite teachers").font(Theme.title).foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 22).frame(minHeight: 44).background(Theme.accent, in: Capsule())
            }
            .accessibilityIdentifier("invite-card-button")
        }
        .frame(maxWidth: .infinity).padding(22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16).padding(.top, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invite-card")
    }
}
