import SwiftUI
import XCTest
@testable import Lime

/// LIME-168: lime's own text size and typeface.
final class TextPreferencesTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "lime.test.text.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testByDefaultLimeFollowsThePhoneAndUsesTheSystemFont() {
        let preferences = TextPreferences(defaults: defaults())
        XCTAssertTrue(preferences.followsSystem)
        XCTAssertNil(preferences.override, "no override: the iPhone's text size")
        XCTAssertNil(preferences.overrideCategory)
        XCTAssertEqual(preferences.typeface, .system)
        XCTAssertEqual(preferences.step, TextStep.defaultStep)
        XCTAssertEqual(TextStep.all[TextStep.defaultStep].size, .large, "Default is the iPhone's Large")
    }

    func testTheChoicesPersistAcrossARestart() {
        let d = defaults()
        let first = TextPreferences(defaults: d)
        first.followsSystem = false
        first.step = 5
        first.typeface = .newsreader
        let second = TextPreferences(defaults: d)
        XCTAssertFalse(second.followsSystem)
        XCTAssertEqual(second.step, 5)
        XCTAssertEqual(second.typeface, .newsreader)
        XCTAssertEqual(second.override, .accessibility2)
        second.followsSystem = true
        XCTAssertNil(TextPreferences(defaults: d).override, "back on the phone's size")
    }

    func testSevenStepsFromExtraSmallToTheLargestAccessibilitySize() {
        XCTAssertEqual(TextStep.all.count, 7)
        XCTAssertEqual(TextStep.all.first?.size, .xSmall)
        XCTAssertEqual(TextStep.all.last?.size, .accessibility5)
        XCTAssertEqual(TextStep.all.map(\.name), ["Extra Small", "Small", "Default", "Large", "Extra Large", "Accessibility", "Largest"])
        let sizes = TextStep.all.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted(), "each step is larger than the one before")
    }

    func testAStepOutOfRangeIsKeptInside() {
        let preferences = TextPreferences(defaults: defaults())
        preferences.step = 99
        XCTAssertEqual(preferences.step, 6)
        preferences.step = -3
        XCTAssertEqual(preferences.step, 0)
    }

    func testLaunchArgumentsArriveAsTextAndStillCount() {
        let d = defaults()
        d.set("NO", forKey: TextPreferences.followKey)
        d.set("6", forKey: TextPreferences.stepKey)
        d.set("figtree", forKey: TextPreferences.fontKey)
        let preferences = TextPreferences(defaults: d)
        XCTAssertFalse(preferences.followsSystem)
        XCTAssertEqual(preferences.step, 6)
        XCTAssertEqual(preferences.typeface, .figtree)
        // Reading them must not write them back: a launch argument is for that launch only.
        XCTAssertEqual(d.string(forKey: TextPreferences.followKey), "NO")
        XCTAssertEqual(d.string(forKey: TextPreferences.stepKey), "6")
    }

    func testLoadingTheDefaultsWritesNothing() {
        let d = defaults()
        _ = TextPreferences(defaults: d)
        XCTAssertNil(d.object(forKey: TextPreferences.followKey))
        XCTAssertNil(d.object(forKey: TextPreferences.stepKey))
        XCTAssertNil(d.object(forKey: TextPreferences.fontKey))
    }

    func testEveryTypefaceHasItsFourWeightsBundledAndRegistered() {
        FontRegistrar.registerAll()
        for face in LimeTypeface.allCases {
            for weight in [Font.Weight.regular, .medium, .semibold, .bold] {
                guard let name = face.postScriptName(for: weight) else { XCTAssertEqual(face, .system); continue }
                XCTAssertNotNil(UIFont(name: name, size: 17), "\(name) is bundled and registered")
            }
        }
        XCTAssertEqual(LimeTypeface.figtree.postScriptName(for: .black), "Figtree-Bold", "the nearest weight")
        XCTAssertEqual(LimeTypeface.plexMono.postScriptName(for: .light), "IBMPlexMono-Regular")
    }

    func testTheComposersFontFollowsTheTypefaceAndTheSize() {
        FontRegistrar.registerAll()
        let preferences = TextPreferences.shared
        let saved = (preferences.followsSystem, preferences.step, preferences.typeface)
        defer { (preferences.followsSystem, preferences.step, preferences.typeface) = saved }
        preferences.followsSystem = false
        preferences.typeface = .system
        preferences.step = 2
        let normal = ComposerDocument.baseFont()
        preferences.step = 6
        let largest = ComposerDocument.baseFont()
        XCTAssertGreaterThan(largest.pointSize, normal.pointSize * 1.8, "the largest accessibility size is much bigger")
        preferences.typeface = .figtree
        XCTAssertEqual(ComposerDocument.baseFont().familyName, "Figtree")
        // Italic in a face with no italic still shows a slant; bold finds the bold file.
        let base = ComposerDocument.baseFont()
        XCTAssertTrue(ComposerDocument.styled(base, traits: [.traitBold]).fontName.contains("Bold"))
        let slanted = ComposerDocument.styled(base, traits: [.traitItalic])
        XCTAssertNotEqual(slanted.fontDescriptor.matrix, CGAffineTransform.identity, "synthetic slant")
    }
}
