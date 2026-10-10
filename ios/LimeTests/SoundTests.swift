import AVFoundation
import XCTest
@testable import Lime

final class SoundFileTests: XCTestCase {
    func testTheBundleHasTheChimeAndTheRingtoneWithinTheirLimits() throws {
        let chime = try XCTUnwrap(Bundle.main.url(forResource: "lime-chime", withExtension: "caf"), "lime-chime.caf is bundled")
        let ring = try XCTUnwrap(Bundle.main.url(forResource: "lime-ring", withExtension: "caf"), "lime-ring.caf is bundled")
        XCTAssertLessThanOrEqual(try XCTUnwrap(CustomSounds.duration(of: chime)), 2.0, "a message chime is at most 2 s")
        XCTAssertLessThan(try XCTUnwrap(CustomSounds.duration(of: ring)), 30.0, "iOS plays a notification sound for under 30 s")
        XCTAssertEqual(SoundFiles.chime, "lime-chime.caf")
        XCTAssertEqual(CallRingtone.callKitSoundName, "lime-ring.caf")
    }
}

@MainActor
final class CustomSoundTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("sounds-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    private func store() -> CustomSounds {
        CustomSounds(directory: folder, defaults: UserDefaults(suiteName: "lime.test.sounds.\(UUID().uuidString)")!)
    }

    /// A 4-second tone to pick from.
    private func tone(seconds: Double = 4) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44_100)) * 0.3 }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
        try file.write(from: buffer)
        return url
    }

    func testAFileIsTrimmedToTheLimitConvertedAndKeptThenRenamedAndDeleted() throws {
        let sounds = store()
        let source = try tone()
        let message = try sounds.add(from: source, start: 0.5, length: 3.5, name: "  Bell  ", kind: .message)
        XCTAssertEqual(message.name, "Bell")
        XCTAssertLessThanOrEqual(message.seconds, 2.01, "a message sound is cut to 2 s whatever was asked")
        XCTAssertEqual(try XCTUnwrap(CustomSounds.duration(of: sounds.fileURL(message.id))), message.seconds, accuracy: 0.05)
        XCTAssertEqual(sounds.fileURL(message.id).pathExtension, "caf")
        let call = try sounds.add(from: source, start: 0, length: 3.5, name: "", kind: .call)
        XCTAssertEqual(call.name, "My sound")
        XCTAssertEqual(call.seconds, 3.5, accuracy: 0.05, "a call sound can be longer")
        XCTAssertEqual(sounds.items(of: .message).count, 1)
        sounds.rename(message.id, to: "Chime two")
        XCTAssertEqual(sounds.item(message.id)?.name, "Chime two")
        sounds.delete(message.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sounds.fileURL(message.id).path))
        XCTAssertNil(sounds.item(message.id))
        // Kept on this phone's own storage, not backed up.
        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testAtMostTenAndAnUnreadableFileIsRefused() throws {
        let sounds = store()
        let source = try tone(seconds: 1)
        for i in 0..<CustomSounds.limit { _ = try sounds.add(from: source, start: 0, length: 1, name: "s\(i)", kind: .message) }
        XCTAssertThrowsError(try sounds.add(from: source, start: 0, length: 1, name: "eleventh", kind: .message)) { XCTAssertEqual($0 as? CustomSounds.Failure, .tooMany) }
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk.caf")
        try Data("not audio".utf8).write(to: junk)
        sounds.delete(sounds.items[0].id)
        XCTAssertThrowsError(try sounds.add(from: junk, start: 0, length: 1, name: "x", kind: .message)) { XCTAssertEqual($0 as? CustomSounds.Failure, .unreadable) }
    }
}

@MainActor
final class DefaultSoundTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "lime.test.defaultsound.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testAFreshInstallAndAnUpgradedOneWithNoStoredKeyBothPlayTheLimeChime() {
        let fresh = NotificationSettings(defaults: defaults())
        XCTAssertEqual(fresh.sound, .limeChime)
        XCTAssertEqual(fresh.sound.fileName, "lime-chime.caf", "the file both the banner and the notification play")
        // An older install that never touched the picker has nothing stored at all.
        let upgraded = defaults()
        upgraded.set(true, forKey: "lime.notify.enabled")
        XCTAssertEqual(NotificationSettings(defaults: upgraded).sound, .limeChime)
        // The stored value is readable by anything that asks the defaults directly, not only by this class.
        XCTAssertEqual(upgraded.string(forKey: "lime.notify.sound"), "limeChime")
    }

    func testADefaultStoredBeforeTheChimeExistedBecomesTheChimeOnceButALaterChoiceSticks() {
        let d = defaults()
        d.set("systemDefault", forKey: "lime.notify.sound")   // what an older build wrote when the picker was touched
        XCTAssertEqual(NotificationSettings(defaults: d).sound, .limeChime, "never a deliberate choice then")
        let settings = NotificationSettings(defaults: d)
        settings.sound = .systemDefault   // now it is a choice
        XCTAssertEqual(NotificationSettings(defaults: d).sound, .systemDefault)
        settings.sound = .none
        XCTAssertEqual(NotificationSettings(defaults: d).sound, NotificationSound.none)
    }
}
