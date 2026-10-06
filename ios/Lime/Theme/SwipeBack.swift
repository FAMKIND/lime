import SwiftUI
import UIKit

/// Hiding the navigation bar disables UIKit's edge-swipe back. This turns it back on so the
/// custom glass header keeps the standard iOS gesture.
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = Self.navigationController(for: gestureRecognizer.view) else { return false }
        return nav.viewControllers.count > 1
    }

    private static func navigationController(for view: UIView?) -> UINavigationController? {
        var responder: UIResponder? = view
        while let r = responder {
            if let nav = r as? UINavigationController { return nav }
            responder = r.next
        }
        return nil
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = SwipeBackDelegate.shared
            pop.isEnabled = true
        }
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
}

extension View {
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}
