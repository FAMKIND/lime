import AVFoundation
import AVKit
import UIKit
@preconcurrency import WebRTC

/// What a call needs from system Picture in Picture (LIME-118c): the other person's video in iOS's floating window, like FaceTime over
/// Messages. Tests use a fake.
@MainActor
protocol CallPiP: AnyObject {
    var isPossible: Bool { get }
    /// The window came up (lime is still in front, or was left).
    var onStarted: (() -> Void)? { get set }
    /// The window is gone (closed by the person, or restored).
    var onStopped: (() -> Void)? { get set }
    /// The person tapped the window to come back to lime's full call screen.
    var onRestore: (() -> Void)? { get set }
    /// The system could not start it.
    var onFailed: (() -> Void)? { get set }
    /// Makes it ready to start (also automatically when lime is left): `sourceView` is the call screen's picture, which must be on screen.
    func prepare(sourceView: UIView)
    func start()
    func stop()
}

/// Draws the other side's frames with an `AVSampleBufferDisplayLayer`, the only kind of content system Picture in Picture can show for a call.
final class PiPDisplayView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()
    /// The frames' rotation in degrees (0, 90, 180, 270): the layer is turned to match.
    var rotation = 0 { didSet { if rotation != oldValue { setNeedsLayout() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(displayLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sideways = rotation == 90 || rotation == 270
        let size = sideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.bounds = CGRect(origin: .zero, size: size)
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(rotation) * .pi / 180))
        CATransaction.commit()
    }
}

/// Receives the remote WebRTC frames and hands them to the display layer as sample buffers (hardware-decoded frames already are pixel
/// buffers; software-decoded I420 ones are copied into an NV12 buffer).
final class PiPFrameRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    /// The layer's own renderer (iOS 17): unlike the layer it may be fed from the WebRTC thread.
    private nonisolated(unsafe) let renderer: AVSampleBufferVideoRenderer
    private let sizeChanged: @Sendable (CGSize, Int) -> Void
    private var lastSize = CGSize.zero, lastRotation = -1

    @MainActor init(layer: AVSampleBufferDisplayLayer, sizeChanged: @escaping @Sendable (CGSize, Int) -> Void) {
        self.renderer = layer.sampleBufferRenderer
        self.sizeChanged = sizeChanged
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let pixels = Self.pixelBuffer(of: frame), let sample = Self.sampleBuffer(pixels, timestampNs: frame.timeStampNs) else { return }
        let rotation = frame.rotation.rawValue
        let size = CGSize(width: Int(frame.width), height: Int(frame.height))
        if size != lastSize || rotation != lastRotation {
            lastSize = size; lastRotation = rotation
            sizeChanged(size, rotation)
        }
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }

    static func pixelBuffer(of frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let native = frame.buffer as? RTCCVPixelBuffer { return native.pixelBuffer }
        let i420 = frame.buffer.toI420()
        let width = Int(i420.width), height = Int(i420.height)
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &made) == kCVReturnSuccess, let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0), let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for row in 0..<height { memcpy(yBase + row * yStride, i420.dataY + row * Int(i420.strideY), width) }
        let chromaWidth = (width + 1) / 2, chromaHeight = (height + 1) / 2
        for row in 0..<chromaHeight {
            let u = i420.dataU + row * Int(i420.strideU), v = i420.dataV + row * Int(i420.strideV)
            let out = (uvBase + row * uvStride).assumingMemoryBound(to: UInt8.self)
            for column in 0..<chromaWidth { out[2 * column] = u[column]; out[2 * column + 1] = v[column] }
        }
        return buffer
    }

    static func sampleBuffer(_ pixels: CVPixelBuffer, timestampNs: Int64) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: timestampNs, timescale: 1_000_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

/// System Picture in Picture for a video call: lime stays in front when it starts, as FaceTime does over Messages, and it also starts
/// by itself when lime is left. The window has only the system's own controls (return, close); mute and end stay on the call screen.
@MainActor
final class CallPictureInPicture: NSObject, CallPiP, AVPictureInPictureControllerDelegate {
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    var onRestore: (() -> Void)?
    var onFailed: (() -> Void)?

    private let media: WebRTCMedia
    private let display = PiPDisplayView()
    private let contentController = AVPictureInPictureVideoCallViewController()
    private var controller: AVPictureInPictureController?
    private var renderer: PiPFrameRenderer?

    init(media: WebRTCMedia) {
        self.media = media
        super.init()
        contentController.view.addSubview(display)
        display.frame = contentController.view.bounds
        display.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentController.preferredContentSize = CGSize(width: 480, height: 640)
        let renderer = PiPFrameRenderer(layer: display.displayLayer) { [weak self] size, rotation in
            Task { @MainActor in self?.frameSizeChanged(size, rotation) }
        }
        self.renderer = renderer
        media.setPictureInPictureRenderer(renderer)
    }

    var isPossible: Bool { AVPictureInPictureController.isPictureInPictureSupported() && (controller?.isPictureInPicturePossible ?? false) }

    func prepare(sourceView: UIView) {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: contentController)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.controller = controller
        CallDiagnostics.shared.log("pip prepared")
    }

    func start() {
        guard let controller, controller.isPictureInPicturePossible else { onFailed?(); return }
        controller.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
        media.setPictureInPictureRenderer(nil)
        renderer = nil
        controller = nil
    }

    private func frameSizeChanged(_ size: CGSize, _ rotation: Int) {
        display.rotation = rotation
        let sideways = rotation == 90 || rotation == 270
        contentController.preferredContentSize = sideways ? CGSize(width: size.height, height: size.width) : size
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in CallDiagnostics.shared.log("pip started"); self.onStarted?() }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in CallDiagnostics.shared.log("pip failed: \(error.localizedDescription)"); self.onFailed?() }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in CallDiagnostics.shared.log("pip stopped"); self.onStopped?() }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in self.onRestore?(); done(true) }
    }
}
