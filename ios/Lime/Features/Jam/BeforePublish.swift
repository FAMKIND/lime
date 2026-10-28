import SwiftUI

/// What is being posted, for the second step.
enum PostStepKind { case post, article, podcast }

/// Step 2 of 2 (LIME-240): **Before you post** (a post) or **Before you publish** (an article or a podcast). Writing is step 1; here the writer decides who can
/// read it (Audience), what it is about (Tags), the series (articles and podcasts), and, for an Everyone post with a photo, video or audio, confirms the student-privacy
/// check. The one primary button is **Post**, **Publish** or (editing) **Update**. Going back to writing loses nothing.
struct BeforePublishScreen: View {
    let kind: PostStepKind
    var editing = false
    /// The title or the first line, and a small picture, to remind what is going out.
    let summary: String
    var thumbnail: UIImage? = nil
    @Binding var audience: String
    @Binding var topics: [String]
    @Binding var series: SeriesInfo?
    /// The audience the post being edited has now.
    var savedAudience: String? = nil
    /// The post has a photo, video or audio (so Everyone asks for the privacy confirmation), and the pictures to check for faces.
    var hasMedia = false
    var pictures: [Data] = []
    var working = false
    var problem: String? = nil
    var buttonID = "jam-post"
    let action: () -> Void
    @Environment(ConversationStore.self) private var store
    @State private var confirmed = false

    private var title: String { kind == .post ? "Before you post" : "Before you publish" }
    private var buttonTitle: String { editing ? "Update" : kind == .post ? "Post" : "Publish" }
    /// Everyone with media needs the confirmation, unless the post was Everyone already.
    private var needsPrivacy: Bool { audience == "everyone" && hasMedia && savedAudience != "everyone" }
    private var showsAudience: Bool { store.openPostsEnabled || audience == "everyone" || savedAudience == "everyone" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Step 2 of 2").font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                HStack(spacing: 12) {
                    if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).accessibilityHidden(true) }
                    Text(summary.isEmpty ? "Your post" : summary).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                        .accessibilityIdentifier("before-summary")
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    if showsAudience { row("Audience", id: "before-audience") { AudienceChip(audience: $audience, saved: savedAudience) } }
                    if store.openPostsEnabled { row("Tags", id: "before-tags") { TopicsChip(topics: $topics) } }
                    if kind != .post { row("Series", id: "before-series") { SeriesChip(series: $series) } }
                }
                if needsPrivacy { StudentPrivacyBlock(pictures: pictures, confirmed: $confirmed) }
                if let problem { Text(problem).font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("before-problem") }
                Button(action: action) {
                    Text(working ? "\(buttonTitle)\u{2026}" : buttonTitle).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Theme.accent.opacity(canGo ? 1 : 0.4), in: Capsule())
                }
                .buttonStyle(.plain).disabled(!canGo)
                .accessibilityLabel(buttonTitle).accessibilityIdentifier(buttonID)
            }
            .padding(20)
        }
        .background(Theme.canvas)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .onAppear { AccessibilityNotification.Announcement("Step 2 of 2, \(title.lowercased())").post() }
    }

    private var canGo: Bool { !working && (!needsPrivacy || confirmed) }

    private func row<Content: View>(_ label: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(Theme.body).foregroundStyle(Theme.text)
                Spacer(minLength: 12)
                content()
            }
            .frame(minHeight: 52)
            Divider().overlay(Theme.hairline)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}
