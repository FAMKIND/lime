import SwiftUI
import Vision

/// When an account may post to Everyone (LIME-210d, choice (g)): a new account waits **7 days** after sign-up, the plainest brake on a throwaway account
/// posting to the world. Kept on this phone; the server's own first-week limit (10 open posts a day) stays as well.
enum AccountAge {
    static let key = "lime.account.since"
    static let waitDays = 7

    /// Remembered the first time this phone registers an account.
    static func noteRegistered() {
        if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(Date(), forKey: key) }
    }

    /// The day Everyone opens for this account, or nil when it is open already.
    static func everyoneOpensOn(now: Date = Date()) -> Date? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-new-account") { return Calendar.current.date(byAdding: .day, value: 3, to: now) }
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-chat") { return nil }
        #endif
        guard let since = UserDefaults.standard.object(forKey: key) as? Date, let opens = Calendar.current.date(byAdding: .day, value: waitDays, to: since) else { return nil }
        return opens > now ? opens : nil
    }
}

/// A face check done **on this phone** (Vision); nothing is sent anywhere. It warns, it never blocks: a classroom photo is the likeliest breach.
enum FaceCheck {
    /// How many of these pictures (JPEG or PNG bytes) show at least one face.
    static func picturesWithFaces(_ pictures: [Data]) async -> Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-faces") { return pictures.isEmpty ? 0 : 1 }
        #endif
        return await Task.detached(priority: .utility) {
            var found = 0
            for data in pictures where !data.isEmpty {
                let request = VNDetectFaceRectanglesRequest()
                if (try? VNImageRequestHandler(data: data, options: [:]).perform([request])) != nil, !(request.results ?? []).isEmpty { found += 1 }
            }
            return found
        }.value
    }
}

/// One post waiting for its privacy confirmation.
struct PrivacyAsk: Identifiable {
    let id = UUID()
    /// The pictures (and video posters) in the post, to check for faces; empty for a post that only has a video or a recording.
    let pictures: [Data]
    let proceed: () -> Void
}

/// Before an Everyone post with a photo, video or audio (LIME-210d, `docs/jam.md` 13.9): the notice, a **required** confirmation for this post, and
/// a warning when the phone finds faces in a photo. Nothing here goes to the server.
struct StudentPrivacySheet: View {
    let ask: PrivacyAsk
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var faces = 0
    @State private var checked = false
    @State private var guidance = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("No students can be identified: faces, names or voices.").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("privacy-notice")
                    Text("Everyone on lime can see this post. Only share students with their family\u{2019}s permission.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    if faces > 0 {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.crop.square").font(.system(size: 18)).foregroundStyle(Theme.text).accessibilityHidden(true)
                            Text(faces == 1 ? "This photo has faces. Check you have permission, or choose another photo." : "These photos have faces. Check you have permission, or choose other photos.")
                                .font(Theme.body).foregroundStyle(Theme.text)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("privacy-faces")
                    }
                    Toggle(isOn: $confirmed) {
                        Text("I have permission to share any students who appear or are heard").font(Theme.body).foregroundStyle(Theme.text)
                    }
                    .toggleStyle(CheckToggleStyle())
                    .accessibilityIdentifier("privacy-confirm")
                    Button { guidance = true } label: { Text("Read the guidance").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.linkOther).frame(minHeight: 44) }
                        .buttonStyle(.plain).accessibilityIdentifier("privacy-guidance")
                    Button { dismiss(); ask.proceed() } label: {
                        Text("Post to everyone").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.accentInk).frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.accent.opacity(confirmed ? 1 : 0.4), in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(!confirmed).accessibilityIdentifier("privacy-post")
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Before you post").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("privacy-cancel") } }
            .sheet(isPresented: $guidance) { StudentPrivacyGuide() }
            .task { faces = await FaceCheck.picturesWithFaces(ask.pictures); checked = true }
        }
        .presentationDetents([.large])
    }
}

/// A checkbox in place of the switch: this is a promise, not a setting.
private struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square").font(.system(size: 24)).foregroundStyle(configuration.isOn ? Theme.text : Theme.textSecondary).accessibilityHidden(true)
                configuration.label.multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        .accessibilityValue(configuration.isOn ? "Confirmed" : "Not confirmed")
    }
}

/// The guidance page: what is safe to share and what is not, in plain words.
struct StudentPrivacyGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    block("Safe to share", "Your own work, lesson plans, anonymous work samples, a wall display with no names, pictures of objects, hands only, backs of heads.")
                    block("Ask first", "Any child\u{2019}s face, name, voice or handwriting with their name, a class list, a school uniform or sign that tells where they are. You need the family\u{2019}s permission, and your school\u{2019}s rules may need more.")
                    block("Subscribers or Everyone?", "A post for subscribers is end-to-end encrypted. A post for Everyone is readable by anyone on lime and by lime\u{2019}s server, and people may save or copy it. When in doubt, keep it for subscribers.")
                    block("If you made a mistake", "Edit the post and choose Subscribers, or delete it. Anyone who already saw it may still have it, so tell the family and your school.")
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Sharing students").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("privacy-guide-done") } }
        }
        .accessibilityIdentifier("privacy-guide")
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text(text).font(Theme.body).foregroundStyle(Theme.textSecondary)
        }
    }
}
