import SwiftUI
import UIKit

/// One photo in the viewer, with Apple's gestures (LIME-211): a `UIScrollView` that zooms around the fingers (1× to 5×, with a rubber-band), pans with
/// momentum and bounce once zoomed, zooms to the tapped point on a double tap, and (not zoomed) follows a downward drag to dismiss. A single tap
/// shows or hides the bars. Zoomed in, pushing past an edge hands the swipe to the next or previous photo, as Photos does.
struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    /// Whether this is the photo on screen (the others sit at 1×).
    var active = true
    var onZoom: (Bool) -> Void = { _ in }
    var onSingleTap: () -> Void = {}
    /// 0...1 while a downward drag is under way (the background fades); the drag ended: dismiss or spring back.
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    /// Zoomed in and pushed past the left (-1) or right (+1) edge.
    var onEdgePush: (Int) -> Void = { _ in }
    var reduceMotion = false

    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.delegate = context.coordinator
        view.imageView.image = image
        context.coordinator.view = view
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: double)
        view.addGestureRecognizer(single)
        let down = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissPan(_:)))
        down.delegate = context.coordinator
        view.addGestureRecognizer(down)
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "photo-zoom"
        view.accessibilityLabel = "Photo"
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in") { [weak view] _ in view.map { $0.setZoomScale(min($0.zoomScale * 2, $0.maximumZoomScale), animated: true) }; return true },
            UIAccessibilityCustomAction(name: "Zoom out") { [weak view] _ in view.map { $0.setZoomScale(max($0.zoomScale / 2, 1), animated: true) }; return true },
        ]
        return view
    }

    func updateUIView(_ view: PhotoScrollView, context: Context) {
        context.coordinator.parent = self
        if view.imageView.image !== image { view.imageView.image = image; view.setNeedsLayout() }
        if !active && view.zoomScale != 1 { view.setZoomScale(1, animated: false) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomablePhoto
        weak var view: PhotoScrollView?
        init(_ parent: ZoomablePhoto) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? PhotoScrollView)?.imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? PhotoScrollView)?.centre()
            parent.onZoom(scrollView.zoomScale > 1.02)
            scrollView.accessibilityValue = scrollView.zoomScale > 1.02 ? "Zoomed \(Int((scrollView.zoomScale * 100).rounded()))%" : nil
        }

        /// Zoomed in, a push past an edge moves to the neighbouring photo.
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            guard scrollView.zoomScale > 1.02 else { return }
            let x = scrollView.contentOffset.x + scrollView.adjustedContentInset.left
            let max = scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.left
            if x < -60 { parent.onEdgePush(-1) } else if x > max + 60 { parent.onEdgePush(1) }
        }

        @objc func singleTap() { parent.onSingleTap() }

        @objc func doubleTap(_ tap: UITapGestureRecognizer) {
            guard let view else { return }
            if view.zoomScale > 1.02 { view.setZoomScale(1, animated: true); return }
            // In to 2.5× at the tapped point.
            let scale: CGFloat = 2.5
            let point = tap.location(in: view.imageView)
            let size = CGSize(width: view.bounds.width / scale, height: view.bounds.height / scale)
            view.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }

        @objc func dismissPan(_ pan: UIPanGestureRecognizer) {
            guard let view else { return }
            let t = pan.translation(in: view)
            switch pan.state {
            case .changed:
                let y = max(t.y, 0)
                view.imageView.transform = CGAffineTransform(translationX: t.x * 0.6, y: y).scaledBy(x: 1 - min(y / 1200, 0.25), y: 1 - min(y / 1200, 0.25))
                parent.onDismissProgress(min(y / 300, 1))
            case .ended, .cancelled:
                if t.y > 120 || pan.velocity(in: view).y > 900 { parent.onDismiss() }
                else {
                    UIView.animate(withDuration: parent.reduceMotion ? 0 : 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: []) { view.imageView.transform = .identity }
                    parent.onDismissProgress(0)
                }
            default: break
            }
        }

        /// The downward drag only starts when the photo is not zoomed and the drag is mostly vertical and down; it never blocks the page swipe.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view else { return true }
            let v = pan.velocity(in: view)
            return view.zoomScale <= 1.02 && v.y > 0 && abs(v.y) > abs(v.x) * 1.5
        }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { false }
    }
}

/// The scroll view: the picture fitted inside it at 1×, kept centred while zoomed.
final class PhotoScrollView: UIScrollView {
    let imageView = UIImageView()
    private var fittedFor: CGSize = .zero

    init() {
        super.init(frame: .zero)
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        alwaysBounceHorizontal = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A new size (a rotation) or a new picture: fit again from 1×.
        if fittedFor != bounds.size, bounds.width > 0, let image = imageView.image {
            fittedFor = bounds.size
            zoomScale = 1
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * fit, height: image.size.height * fit))
            contentSize = imageView.frame.size
        }
        centre()
    }

    func centre() {
        let x = max((bounds.width - imageView.frame.width) / 2, 0), y = max((bounds.height - imageView.frame.height) / 2, 0)
        imageView.frame.origin = CGPoint(x: x, y: y)
    }
}
