import AVFoundation
import XCTest
@testable import Lime

/// Voice messages and video: the recorder's note, the bars, the clock, and the video limits (3 minutes, 50 MB).
@MainActor
final class VoiceVideoTests: XCTestCase {
    func testTheWaveformIs64BarsFromTheLoudestSampleOfEachStretch() {
        XCTAssertEqual(VoiceRecorder.bars([]).count, 64)
        let quietThenLoud = [Float](repeating: 0.1, count: 100) + [Float](repeating: 0.9, count: 100)
        let bars = VoiceRecorder.bars(quietThenLoud)
        XCTAssertEqual(bars.count, 64)
        XCTAssertLessThan(bars[10], 60)
        XCTAssertGreaterThan(bars[60], 200)
        XCTAssertGreaterThanOrEqual(bars.min() ?? 0, 8, "silence still shows a small bar")
        XCTAssertEqual(VoiceRecorder.bars([2.0]).max(), 255, "never above the top")
    }

    func testTheClockReadsLikeAVoiceMessage() {
        XCTAssertEqual(VoiceFormat.clock(0), "0:00")
        XCTAssertEqual(VoiceFormat.clock(7.4), "0:07")
        XCTAssertEqual(VoiceFormat.clock(83), "1:23")
        XCTAssertEqual(VoiceFormat.clock(3723), "1:02:03")
    }

    func testASimulatedRecordingGivesANoteAndAShortOneIsDropped() async throws {
        let recorder = VoiceRecorder()
        recorder.simulated = true
        let started = await recorder.start()
        XCTAssertTrue(started)
        XCTAssertEqual(recorder.phase, .recording)
        recorder.lock()
        XCTAssertEqual(recorder.phase, .locked)
        try await Task.sleep(for: .milliseconds(800))
        let note = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertGreaterThanOrEqual(note.durationMs, 600)
        XCTAssertEqual(note.waveform.count, 64)

        _ = await recorder.start()
        XCTAssertNil(recorder.finish(), "a tap is not a voice message")
        _ = await recorder.start()
        recorder.cancel()
        XCTAssertEqual(recorder.phase, .idle)
    }

    func testPlaybackSpeedGoesOneOnePointFiveTwoAndRoundAndTheNextVoiceMessagePlaysOn() async throws {
        let player = VoicePlayer()
        XCTAssertEqual(player.rate, 1)
        player.cycleRate(); XCTAssertEqual(player.rate, 1.5)
        player.cycleRate(); XCTAssertEqual(player.rate, 2)
        player.cycleRate(); XCTAssertEqual(player.rate, 1)

        player.simulated = true
        let a = AttachmentItem(id: "a", mime: "audio/mp4", name: "a", size: 1, durationMs: 400, downloaded: true)
        let b = AttachmentItem(id: "b", mime: "audio/mp4", name: "b", size: 1, durationMs: 60_000, downloaded: true)
        await player.toggle(a, after: { $0 == "a" ? b : nil }, data: { _ in Data(count: 10) })
        XCTAssertTrue(player.isCurrent("a"))
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertTrue(player.isCurrent("b"), "the next voice message started by itself")
        player.stop()
    }

    // MARK: Video

    /// A tiny H.264 video of `seconds` seconds (one frame a second).
    private func makeVideo(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let size = CGSize(width: 320, height: 240)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<seconds {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(40 + frame % 200), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(seconds: Double(frame), preferredTimescale: 600))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return url
    }

    func testAShortVideoIsPreparedWithADurationAPosterAndATinyThumbnail() async throws {
        let url = try await makeVideo(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let made = try await VideoProcessing.prepare(url) { _ in }
        XCTAssertEqual(made.item.mime, "video/mp4")
        XCTAssertEqual(Double(made.item.durationMs ?? 0), 3000, accuracy: 600)
        XCTAssertGreaterThan(made.item.width ?? 0, 0)
        XCTAssertLessThan(made.item.bytes.count, VideoProcessing.maxBytes)
        XCTAssertFalse(made.item.thumb.isEmpty)
        XCTAssertLessThanOrEqual(made.item.thumb.count, AttachmentProcessing.maxThumbBytes)
        XCTAssertNotNil(made.poster)
    }

    func testAFourMinuteVideoIsRefusedWithAClearMessage() async throws {
        let url = try await makeVideo(seconds: 240)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await VideoProcessing.prepare(url) { _ in }
            XCTFail("a 4-minute video must be refused")
        } catch let problem as VideoProcessing.Problem {
            XCTAssertEqual(problem, .tooLong(seconds: 240))
            XCTAssertEqual(VideoProcessing.message(for: problem), "That video is 4:00 long. Videos can be up to 3 minutes.")
        }
        XCTAssertTrue(VideoProcessing.message(for: .tooLarge).contains("50 MB"))
    }
}
