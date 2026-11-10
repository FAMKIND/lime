import XCTest
@testable import Lime

/// LIME-130-3a: chat and attachments accessibility: the bubble contrast guard, what a message says as one element, the GIF pause rule,
/// the voice message's position, the A–Z rail's steps, sticker names and lookup words.
final class Access130cTests: XCTestCase {
    // 1. Captions on bubbles: 4.5:1 (7:1 with Increase Contrast for the main text) in every theme, light and dark.
    func testSecondaryTextReadsOnTheOtherBubbleAndMyCaptionsOnMyBubbleInEveryTheme() {
        for background in AppThemeBackground.allCases {
            for accent in 0..<8 {
                for dark in [false, true] {
                    for ic in [false, true] {
                        let t = ThemeResolver.resolve(accent: accent, background: background, dark: dark, increaseContrast: ic)
                        let name = "\(background.rawValue) accent \(accent) \(dark ? "dark" : "light")\(ic ? " IC" : "")"
                        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.secondary, t.bubble), 4.5, "secondary on the other bubble, \(name)")
                        XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(t.ownSecondary, t.own), 4.5, "caption on my bubble, \(name)")
                        XCTAssertTrue(t.passes(increaseContrast: ic), name)
                    }
                }
            }
        }
    }

    func testAChatsOwnBubbleColourHasCaptionsThatRead() {
        for tone in 0..<8 { for deep in [false, true] {
            var look = ChatLook(); look.bubbleTone = tone; look.bubbleDeep = deep
            guard let style = look.ownBubble else { return XCTFail("no style") }
            _ = style.secondary
            let (fill, ink) = ChatLook.bubbleColours(tone: tone, deep: deep)
            let soft = ContrastGuard.nudge(ContrastGuard.blend(ink, fill, 0.3), against: [fill], minimum: 4.5)
            XCTAssertGreaterThanOrEqual(ContrastGuard.ratio(soft, fill), 4.5, "tone \(tone) deep \(deep)")
        } }
    }

    // 2. One element per message.
    private func message(own: Bool, text: String = "See you at nine", state: DeliveryState = .received) -> Message {
        Message(id: "m1", senderID: own ? nil : "mei", text: text, date: Date(timeIntervalSince1970: 1_700_000_000), state: state)
    }

    func testAMessageFromSomeoneNamesThemAndAMessageOfMineSaysYou() {
        let theirs = MessageSpeech.label(for: message(own: false), senderName: "Mei Lin")
        XCTAssertTrue(theirs.hasPrefix("Mei Lin, See you at nine, "), theirs)
        let mine = MessageSpeech.label(for: message(own: true, state: .sent), senderName: nil)
        XCTAssertTrue(mine.hasPrefix("You, See you at nine, "), mine)
        XCTAssertTrue(mine.hasSuffix(", sent"), mine)
        XCTAssertFalse(mine.contains("·"))
    }

    func testTheLabelSaysEditedFailedReactionsAndReplies() {
        var m = message(own: true, state: .failed)
        m.edited = true
        m.reactions = [ReactionChip(emoji: "❤️", count: 2, mine: false, people: []), ReactionChip(emoji: "😂", count: 1, mine: true, people: [])]
        m.thread = ThreadInfo(replyCount: 3, lastReplyAt: Date(), repliers: [], unread: 1)
        let label = MessageSpeech.label(for: m, senderName: nil)
        XCTAssertTrue(label.contains(", edited"), label)
        XCTAssertTrue(label.contains("not sent, retry available"), label)
        XCTAssertTrue(label.contains("3 reactions: ❤️ 2, 😂 1 (you)"), label)
        XCTAssertTrue(label.hasSuffix("3 replies, 1 unread"), label)
    }

    func testAGroupMessageAndADeletedOneAndAWaitingOne() {
        XCTAssertTrue(MessageSpeech.label(for: message(own: false), senderName: "Sam").hasPrefix("Sam, "))
        var deleted = message(own: false); deleted.deleted = true
        XCTAssertEqual(MessageSpeech.label(for: deleted, senderName: "Sam"), "Sam, This message was deleted")
        XCTAssertTrue(MessageSpeech.label(for: message(own: true, state: .offline), senderName: nil).hasSuffix("waiting for internet"))
    }

    func testTheHeaderOfAMessageWithMediaLeavesOutTheBody() {
        let header = MessageSpeech.label(for: message(own: false, text: "A caption"), senderName: "Mei Lin", includeBody: false)
        XCTAssertTrue(header.hasPrefix("Mei Lin, "), header)
        XCTAssertFalse(header.contains("A caption"))
    }

    func testAMessageWithAPhotoAndAVoiceMessageSaysWhatKindOfThingItIs() {
        func item(_ mime: String, _ name: String) -> AttachmentItem { AttachmentItem(id: name, mime: mime, name: name, size: 1, width: 1, height: 1, durationMs: 40_000, thumb: Data(), downloaded: true) }
        XCTAssertEqual(MessageSpeech.attachments([item("image/jpeg", "IMG_4821.JPG")]), "Photo")
        XCTAssertEqual(MessageSpeech.attachments([item("image/jpeg", "a"), item("image/jpeg", "b")]), "2 photos")
        XCTAssertEqual(MessageSpeech.attachments([item("audio/m4a", "v")]), "Voice message")
        XCTAssertEqual(MessageSpeech.attachments([item("application/pdf", "plan.pdf")]), "File: plan.pdf")
    }

    func testWebAddressesInTheTextBecomeActions() {
        XCTAssertEqual(MessageSpeech.links(in: "read https://example.com/a now").map(\.host), ["example.com"])
        XCTAssertTrue(MessageSpeech.links(in: "no link here").isEmpty)
    }

    // 8. GIFs.
    func testAGifPlaysUntilItIsPausedAndNeverByItselfWithReduceMotion() {
        XCTAssertTrue(GIFPlayback.plays(reduceMotion: false, asked: false, paused: false))
        XCTAssertFalse(GIFPlayback.plays(reduceMotion: false, asked: false, paused: true), "after its five seconds it stops")
        XCTAssertFalse(GIFPlayback.plays(reduceMotion: true, asked: false, paused: false), "Reduce Motion: not by itself")
        XCTAssertTrue(GIFPlayback.plays(reduceMotion: true, asked: true, paused: false), "tapped to play")
        XCTAssertTrue(GIFPlayback.plays(reduceMotion: false, asked: true, paused: true), "tapped: it keeps playing")
        XCTAssertEqual(GIFPlayback.loopSeconds, 5)
    }

    @MainActor func testTheFiveSecondsPauseIsSkippedForAGifTheTapStarted() {
        let control = GIFPlayback()
        control.toggle("a", reduceMotion: true)          // tapped on with Reduce Motion
        control.loopedEnough("a")
        XCTAssertTrue(control.isPlaying("a", reduceMotion: true))
        control.loopedEnough("b")
        XCTAssertFalse(control.isPlaying("b", reduceMotion: false))
        control.toggle("b", reduceMotion: false)          // Play GIF
        XCTAssertTrue(control.isPlaying("b", reduceMotion: false))
        control.toggle("b", reduceMotion: false)          // Pause GIF
        XCTAssertFalse(control.isPlaying("b", reduceMotion: false))
    }

    // 7. The voice message.
    func testTheVoicePositionAndSkipping() {
        XCTAssertEqual(VoiceFormat.position(progress: 0.3, total: 40), "0:12 of 0:40")
        XCTAssertEqual(VoiceFormat.position(progress: 0, total: 40), "0:00 of 0:40")
        XCTAssertEqual(VoiceFormat.moved(progress: 0.3, total: 40, by: 5), 0.425, accuracy: 0.0001)
        XCTAssertEqual(VoiceFormat.moved(progress: 0.05, total: 40, by: -5), 0)
        XCTAssertEqual(VoiceFormat.moved(progress: 0.95, total: 40, by: 5), 1)
    }

    // 5. The A–Z rail.
    func testTheRailStepsToTheNextLetterThatHasSomeone() {
        let present = ["A", "C", "M"]
        XCTAssertEqual(IndexRail.step(from: nil, among: present, by: 1), "A")
        XCTAssertEqual(IndexRail.step(from: "A", among: present, by: 1), "C")
        XCTAssertEqual(IndexRail.step(from: "M", among: present, by: 1), "M")
        XCTAssertEqual(IndexRail.step(from: "C", among: present, by: -1), "A")
        XCTAssertNil(IndexRail.step(from: nil, among: [], by: 1))
    }

    // 10. Labels.
    func testAReceivedLimeStickerReadsItsName() {
        let pack = [LimeSticker(file: "thank-you", words: "Thank you!", find: [])]
        XCTAssertEqual(StickerPack.spokenName(forFileName: "lime-sticker-thank-you.gif", in: pack), "lime sticker: Thank you!")
        XCTAssertEqual(StickerPack.spokenName(forFileName: "lime-sticker-unknown.gif", in: pack), "Sticker")
        XCTAssertEqual(StickerPack.spokenName(forFileName: "party.gif", in: pack), "Sticker")
    }

    // 3. Lookups.
    func testLookupStatesHaveWords() {
        XCTAssertNil(TeacherLookup.State.idle.spokenWords)
        XCTAssertEqual(TeacherLookup.State.searching.spokenWords, "Searching")
        XCTAssertEqual(TeacherLookup.State.nobody.spokenWords, "No teacher found")
        XCTAssertEqual(TeacherLookup.State.problem("Try again").spokenWords, "Try again")
    }
}
