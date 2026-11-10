import XCTest
import UIKit
@testable import Lime

/// LIME-292b: the icon choices, their asset names and the grid's columns.
final class AppIcon292Tests: XCTestCase {
    func testLimeIsThePrimaryIconAndTheOthersAreNamedSets() {
        XCTAssertNil(AppIconChoice.lime.iconName)
        XCTAssertEqual(AppIconChoice.dark.iconName, "AppIcon-Dark")
        XCTAssertEqual(AppIconChoice.chalkboard.iconName, "AppIcon-Chalkboard")
        XCTAssertEqual(AppIconChoice.choice(forIconName: nil), .lime)
        XCTAssertEqual(AppIconChoice.choice(forIconName: "AppIcon-Pixel"), .pixel)
        XCTAssertEqual(AppIconChoice.choice(forIconName: "Nope"), .lime)
        XCTAssertEqual(AppIconChoice.allCases.count, 8)
    }

    func testEveryChoiceHasItsPreviewImageAndAnSpokenName() {
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.preview), "\(choice.preview) is in the asset catalog")
            XCTAssertEqual(choice.spokenName, "\(choice.title) app icon")
        }
    }

    func testTheGridDropsToThreeThenTwoColumnsAtAccessibilitySizes() {
        XCTAssertEqual(AppIconChoice.columns(for: .large), 4)
        XCTAssertEqual(AppIconChoice.columns(for: .xxxLarge), 4)
        XCTAssertEqual(AppIconChoice.columns(for: .accessibility1), 3)
        XCTAssertEqual(AppIconChoice.columns(for: .accessibility2), 3)
        XCTAssertEqual(AppIconChoice.columns(for: .accessibility3), 2)
        XCTAssertEqual(AppIconChoice.columns(for: .accessibility5), 2)
    }

    func testTheFooterIsSignalsLineWithOurName() {
        XCTAssertEqual(AppIconChoice.footer, "The name \u{201C}lime\u{201D} stays the same on your Home Screen and in notifications.")
    }
}
