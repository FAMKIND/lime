import SwiftUI

/// The jam tab (coming soon): a calm page, no banner. "Notify me" is kept on this phone only.
struct JamPage: View {
    @AppStorage("lime.jamNotify") private var notify = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "book").font(.system(size: 44)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    Text("A place for teachers to share what works: posts, articles and recordings, by teachers, for teachers. Coming soon.")
                        .font(Theme.body).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("jam-text")
                    Toggle(isOn: $notify) {
                        Text("Notify me").font(Theme.body).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)
                    .accessibilityIdentifier("jam-notify")
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("jam")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
