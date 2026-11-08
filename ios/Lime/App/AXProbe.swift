#if DEBUG
import SwiftUI
import UIKit

/// UI tests only (`-lime-ax-probe`, LIME-130-1): XCTest cannot list an element's custom actions or run one by name, so the app walks its own accessibility
/// tree, the same one VoiceOver, Switch Control and Voice Control read, and a test reads the result from a text.
@MainActor
enum AXProbe {
    struct Node { let label: String; let identifier: String; let actions: [UIAccessibilityCustomAction]; let object: NSObject }

    private static func identifier(of object: NSObject) -> String {
        guard object.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return "" }
        return object.value(forKey: "accessibilityIdentifier") as? String ?? ""
    }

    static func nodes() -> [Node] {
        var found: [Node] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, _ depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let label = object.accessibilityLabel ?? ""
            let identifier = identifier(of: object)
            if let actions = object.accessibilityCustomActions, !actions.isEmpty {
                found.append(Node(label: label, identifier: identifier, actions: actions, object: object))
            }
            if let view = object as? UIView {
                for sub in view.subviews { visit(sub, depth + 1) }
                for element in view.accessibilityElements ?? [] { if let e = element as? NSObject { visit(e, depth + 1) } }
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count { if let e = object.accessibilityElement(at: index) as? NSObject { visit(e, depth + 1) } }
            }
            if let elements = object.accessibilityElements { for element in elements { if let e = element as? NSObject { visit(e, depth + 1) } } }
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { visit(window, 0) }
        }
        return found
    }

    /// One line per element that has custom actions: `label | identifier | Action, Action, …`.
    static func dump() -> String {
        nodes().map { "\($0.label) | \($0.identifier) | " + $0.actions.map(\.name).joined(separator: ", ") }.joined(separator: "\n")
    }

    /// An accessibility activation (a VoiceOver double-tap, Switch Control's select, Voice Control's "Tap") of the element with this identifier.
    @discardableResult
    static func activate(_ identifier: String) -> Bool {
        var target: NSObject?
        func visit(_ object: NSObject, _ depth: Int) {
            guard depth < 40, target == nil else { return }
            if Self.identifier(of: object) == identifier, !(object is UIWindow) { target = object; return }
            if let view = object as? UIView { for sub in view.subviews { visit(sub, depth + 1) } }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count { if let e = object.accessibilityElement(at: index) as? NSObject { visit(e, depth + 1) } }
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { visit(window, 0) }
        }
        return target?.accessibilityActivate() ?? false
    }

    /// Runs the action called `name` on the first element that has it.
    @discardableResult
    static func run(_ name: String) -> Bool {
        for node in nodes() {
            if let action = node.actions.first(where: { $0.name == name }) {
                if let handler = action.actionHandler { return handler(action) }
                if let target = action.target { _ = (target as AnyObject).perform(action.selector, with: action); return true }
            }
        }
        return false
    }

    /// The two-finger scrub (Escape): offered to every element, deepest first, until one takes it.
    static func escape() -> Bool {
        var all: [NSObject] = []
        func collect(_ object: NSObject, _ depth: Int) {
            guard depth < 40 else { return }
            all.append(object)
            if let view = object as? UIView { for sub in view.subviews { collect(sub, depth + 1) } }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count { if let e = object.accessibilityElement(at: index) as? NSObject { collect(e, depth + 1) } }
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { collect(window, 0) }
        }
        return all.reversed().contains { $0.accessibilityPerformEscape() }
    }

    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-lime-ax-probe") }
}

/// The probe's three buttons and its output, drawn over the app in probe mode only.
struct AXProbeOverlay: View {
    @State private var output = ""
    var body: some View {
        VStack(spacing: 2) {
            Button("probe-dump") { output = AXProbe.dump() }.accessibilityIdentifier("ax-probe-dump")
            Button("probe-more") { output = "more:\(AXProbe.run("More actions"))" }.accessibilityIdentifier("ax-probe-more")
            Button("probe-mic") { output = "mic:\(AXProbe.activate("composer-mic"))" }.accessibilityIdentifier("ax-probe-mic")
            Button("probe-escape") { output = "escape:\(AXProbe.escape())" }.accessibilityIdentifier("ax-probe-escape")
            Button("probe-dismiss") { output = "dismiss:\(AXProbe.run("Dismiss"))" }.accessibilityIdentifier("ax-probe-dismiss")
            Button("probe-said") { output = "said:" + Announce.said.joined(separator: "|") }.accessibilityIdentifier("ax-probe-said")
            Text(output).font(.system(size: 1)).accessibilityLabel(output).accessibilityIdentifier("ax-probe-out")
        }
        .font(.system(size: 9)).padding(2).background(.yellow.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.bottom, 120)
    }
}
#endif
