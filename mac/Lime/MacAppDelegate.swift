import UIKit

/// Trims the menus Mac Catalyst adds for you down to what lime can do: no New Window, no document items (Duplicate, Move, Rename, Export),
/// (The tab-bar items, Show Tab Bar and Show All Tabs, are added later by AppKit and cannot be removed here.) (SwiftUI `.commands` adds lime's own items in `MacApp.swift`.)
final class MacAppDelegate: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        for id: UIMenu.Identifier in [.newScene, .document, .print, .toolbar, .share, .find, .spelling, .substitutions, .transformations, .speech, .lookup, .learn] {
            builder.remove(menu: id)
        }
    }
}
