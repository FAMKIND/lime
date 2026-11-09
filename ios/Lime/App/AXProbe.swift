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

    /// The elements VoiceOver would stop on, found the way it finds them: an element is a stop and what is inside it is not walked. One line per stop,
    /// `label | identifier`.
    static func stops() -> String {
        var found: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, _ depth: Int) {
            guard depth < 60, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement { found.append("\(object.accessibilityLabel ?? "") | \(identifier(of: object))"); return }
            if let view = object as? UIView { for sub in view.subviews { visit(sub, depth + 1) } }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count { if let e = object.accessibilityElement(at: index) as? NSObject { visit(e, depth + 1) } }
            }
            if let elements = object.accessibilityElements { for element in elements { if let e = element as? NSObject { visit(e, depth + 1) } } }
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { visit(window, 0) }
        }
        return found.joined(separator: "\n")
    }

    /// VoiceOver's swipe up or down on the first element whose identifier starts with `prefix`: an adjustable element's increment or decrement.
    @discardableResult
    static func adjust(_ prefix: String, up: Bool) -> NSObject? {
        var target: NSObject?
        func visit(_ object: NSObject, _ depth: Int) {
            guard depth < 40, target == nil else { return }
            if Self.identifier(of: object).hasPrefix(prefix), object.accessibilityTraits.contains(.adjustable) { target = object; return }
            if let view = object as? UIView { for sub in view.subviews { visit(sub, depth + 1) } }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count { if let e = object.accessibilityElement(at: index) as? NSObject { visit(e, depth + 1) } }
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { visit(window, 0) }
        }
        guard let target else { return nil }
        if up { target.accessibilityIncrement() } else { target.accessibilityDecrement() }
        return target
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

/// Counts every request the app's own URL loading system is asked to make (LIME-130-3b: no network call while a transcript is made). It answers
/// `false` to all of them, so it only counts; it does not take any request over.
final class NetCanary: URLProtocol {
    nonisolated(unsafe) static var seen: [String] = []
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock(); seen.append(request.url?.absoluteString ?? "?"); lock.unlock()
        return false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
    static var count: Int { lock.lock(); defer { lock.unlock() }; return seen.count }
}

/// A second of silence as a WAV file, for the transcript probe.
private func silentWAV() -> Data {
    let rate: UInt32 = 16_000, samples = Int(rate)
    var data = Data()
    func put<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
    data.append("RIFF".data(using: .ascii)!); put(UInt32(36 + samples * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
    put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(rate); put(rate * 2); put(UInt16(2)); put(UInt16(16))
    data.append("data".data(using: .ascii)!); put(UInt32(samples * 2)); data.append(Data(count: samples * 2))
    return data
}

/// The probe's three buttons and its output, drawn over the app in probe mode only.
struct AXProbeOverlay: View {
    @State private var output = ""
    init() {
        if ProcessInfo.processInfo.arguments.contains("-lime-net-canary") { URLProtocol.registerClass(NetCanary.self) }
    }
    var body: some View {
        VStack(spacing: 2) {
            Button("probe-dump") { output = AXProbe.dump() }.accessibilityIdentifier("ax-probe-dump")
            Button("probe-more") { output = "more:\(AXProbe.run("More actions"))" }.accessibilityIdentifier("ax-probe-more")
            Button("probe-mic") { output = "mic:\(AXProbe.activate("composer-mic"))" }.accessibilityIdentifier("ax-probe-mic")
            Button("probe-escape") { output = "escape:\(AXProbe.escape())" }.accessibilityIdentifier("ax-probe-escape")
            Button("probe-dismiss") { output = "dismiss:\(AXProbe.run("Dismiss"))" }.accessibilityIdentifier("ax-probe-dismiss")
            Button("probe-stops") { output = AXProbe.stops() }.accessibilityIdentifier("ax-probe-stops")
            Button("probe-up") {
                let target = AXProbe.adjust("voice-bubble-", up: true)
                Task { try? await Task.sleep(for: .milliseconds(600)); output = "up:\(target != nil) value:\(target?.accessibilityValue ?? "")" }
            }.accessibilityIdentifier("ax-probe-up")
            Button("probe-transcribe") {
                output = "transcribing"
                Task {
                    let outcome = await Transcriber.transcribe(bytes: silentWAV(), fileExtension: "wav", seconds: 1)
                    output = "transcribe:\(outcome) net:\(NetCanary.count)"
                }
            }.accessibilityIdentifier("ax-probe-transcribe")
            Button("probe-net") { output = "net:\(NetCanary.count) \(NetCanary.seen.joined(separator: " "))" }.accessibilityIdentifier("ax-probe-net")
            Button("probe-said") { output = "said:" + Announce.said.joined(separator: "|") }.accessibilityIdentifier("ax-probe-said")
            Text(output).font(.system(size: 1)).accessibilityLabel(output).accessibilityIdentifier("ax-probe-out")
        }
        .font(.system(size: 9)).padding(2).background(.yellow.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.bottom, 120)
    }
}
#endif
