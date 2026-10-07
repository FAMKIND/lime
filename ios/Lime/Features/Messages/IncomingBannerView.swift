import SwiftUI

/// The banner at the top while Lime is open and a message arrives in another chat. Tap it to open the
/// chat; it goes by itself after a few seconds, or when swiped up.
struct IncomingBannerView: View {
    @Environment(NotificationCoordinator.self) private var notifications

    var body: some View {
        ZStack(alignment: .top) {
            if let banner = notifications.banner {
                Button { notifications.openBanner() } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: banner.sender, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(banner.content.title).font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                            Text(banner.content.body).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .limeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 12).padding(.top, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(banner.content.title). \(banner.content.body)")
                .accessibilityHint("Opens the chat")
                .accessibilityIdentifier("incoming-banner")
                .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
                    if drag.translation.height < -10 { notifications.dismissBanner() }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(4.5))
                    if notifications.banner?.id == banner.id { notifications.dismissBanner() }
                }
            }
        }
        .animation(.spring(duration: 0.3), value: notifications.banner)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(notifications.banner != nil)
    }
}
