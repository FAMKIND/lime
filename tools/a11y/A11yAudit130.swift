import XCTest

/// LIME-130 Phase 1: runs Apple's accessibility audit (the same checks as Xcode's Accessibility Inspector audit: contrast, element description, hit region, text clipped, Dynamic Type,
/// traits, parent/child) on one launch of every demo screen, and saves a screenshot of each. Copy into ios/LimeUITests/ to run (not part of the target); results go to $A11Y_OUT as JSON lines.
///   TEST_RUNNER_PASS=default|ax5|dark TEST_RUNNER_A11Y_OUT=/path xcodebuild test -only-testing:LimeUITests/A11yAudit130
@MainActor
final class A11yAudit130: XCTestCase {
    let env = ProcessInfo.processInfo.environment
    var pass: String { env["PASS"] ?? "default" }
    var out: String { env["A11Y_OUT"] ?? "/private/tmp/a11y" }
    let demo = ["-lime-skip-sign-in", "-lime-demo-chat"]

    struct Screen { let name: String; let args: [String]; var steps: ((XCUIApplication) -> Void)? = nil }

    var screens: [Screen] {
        let d = demo
        func s(_ n: String) -> Screen { Screen(name: n, args: d + ["-lime-demo-screen", n]) }
        var list: [Screen] = [
            Screen(name: "signin-welcome", args: ["-lime-fake-auth", "-lime-reset-session", "-lime-reset-store"]),
            Screen(name: "signin-terms", args: ["-lime-fake-auth", "-lime-reset-session", "-lime-reset-store"], steps: { app in
                app.buttons["welcome-continue"].tap()
                let f = app.textFields["identifier-field"]; if f.waitForExistence(timeout: 8) { f.tap(); f.typeText("new.teacher@example.com") }
                app.buttons["next-button"].tap(); app.buttons["confirm-yes"].tap()
                let c = app.textFields["code-field"]; if c.waitForExistence(timeout: 8) { c.tap(); c.typeText("123456") }
                app.buttons["next-button"].tap()
                _ = app.descendants(matching: .any).matching(identifier: "terms-agree").firstMatch.waitForExistence(timeout: 8)
            }),
            Screen(name: "messages", args: d),
            Screen(name: "calls-list", args: d + ["-lime-demo-calls"]),
            Screen(name: "calls-list-many", args: d + ["-lime-demo-calls", "-lime-demo-calls-many"]),
            Screen(name: "call-voice", args: d + ["-lime-demo-call", "voice"]),
            Screen(name: "call-video", args: d + ["-lime-demo-call", "video"]),
            Screen(name: "call-group-4", args: d + ["-lime-demo-screen", "group-call-4"]),
            Screen(name: "call-group-incoming", args: d + ["-lime-demo-screen", "group-incoming"]),
            Screen(name: "move-offer", args: ["-lime-demo-move-offer"]),
            Screen(name: "chat-themed-deep-meadow", args: d + ["-lime-demo-chatlook", "0", "deep", "meadow", "-lime-demo-screen", "chat"]),
            Screen(name: "emoji-gif-panel", args: d + ["-lime-demo-screen", "attachments-gif", "-lime-demo-my-gifs", "-lime.composerPanelTab", "Emoji"]),
            Screen(name: "jam-handover-offer", args: d + ["-lime-demo-screen", "jam", "-lime-demo-handover-offer"]),
            Screen(name: "jam-writer-review", args: d + ["-lime-demo-screen", "jam-mine", "-lime-demo-review-writer"]),
            Screen(name: "jam-band-people-owner", args: d + ["-lime-demo-screen", "jam-mine-profile", "-lime-demo-band-people", "-lime-demo-band-owner"]),
            Screen(name: "jam-mine-open-posts", args: d + ["-lime-demo-screen", "jam-mine", "-lime-demo-open"]),
        ]
        for n in ["chat", "call-bubbles", "format", "attachments-gif", "attachments-remote", "chat-deleted-person", "note-to-self", "group", "group-details", "group-details-plain", "groups-rows",
                  "band-group-rows", "new-group-name", "profile-me", "profile-lee", "profile-sam", "settings", "scan-band", "key-change", "session-ended",
                  "jam", "jam-discover", "jam-following", "jam-mine", "jam-mine-asjam", "jam-mine-podcast", "jam-mine-profile", "jam-series", "jam-community"] { list.append(s(n)) }
        // Settings pages: scroll to the row, open it (and, for Customize, the page inside it)
        func page(_ name: String, _ path: [String]) {
            list.append(Screen(name: name, args: d + ["-lime-demo-screen", "settings"], steps: { app in
                for row in path {
                    var tries = 0
                    let target = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", row)).firstMatch
                    while !(target.exists && target.isHittable) && tries < 8 { app.swipeUp(); tries += 1 }
                    if target.exists { target.tap() } else if app.staticTexts[row].exists { app.staticTexts[row].tap() }
                    sleep(2)
                }
            }))
        }
        page("settings-account", ["Account"]); page("settings-privacy", ["Privacy"]); page("settings-emergency", ["Emergency"]); page("settings-my-gifs", ["My GIFs"])
        page("settings-linked-devices", ["Linked Devices"]); page("settings-work-hours", ["Work hours"]); page("settings-customize", ["Customize"]); page("settings-about", ["About"])
        page("settings-customize-text-size", ["Customize", "Text size"]); page("settings-customize-appearance", ["Customize", "Appearance"]); page("settings-customize-background", ["Customize", "Background"])
        page("settings-notifications-sounds", ["Notifications", "Sound"])
        return list
    }

    func testAll() throws {
        continueAfterFailure = true   // a stale element while reading an issue must not stop the run
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let only = env["ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        for sc in screens where only == nil || only!.contains(sc.name) {
            let app = XCUIApplication(); app.launchArguments = sc.args; app.launch()
            sleep(4)
            sc.steps?(app); sleep(2)
            var issues: [[String: String]] = []
            do {
                try app.performAccessibilityAudit { issue in
                    let e = issue.element
                    issues.append(["type": "\(issue.auditType.rawValue)", "compact": issue.compactDescription, "detail": issue.detailedDescription,
                                   "elementType": e.map { "\($0.elementType.rawValue)" } ?? "", "label": e?.label ?? "", "id": e?.identifier ?? "",
                                   "frame": e.map { "\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)),\(Int($0.frame.width)),\(Int($0.frame.height))" } ?? ""])
                    return true
                }
            } catch { issues.append(["type": "error", "compact": "\(error)"]) }
            let shot = XCUIScreen.main.screenshot().pngRepresentation
            try? shot.write(to: URL(fileURLWithPath: "\(out)/\(pass)-\(sc.name).png"))
            let rec: [String: Any] = ["pass": pass, "screen": sc.name, "count": issues.count, "issues": issues]
            if let data = try? JSONSerialization.data(withJSONObject: rec), let line = String(data: data, encoding: .utf8) {
                let url = URL(fileURLWithPath: "\(out)/\(pass).jsonl")
                if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
                else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
            }
            app.terminate()
        }
    }
}
