import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reports a tap on the tab that is already showing. SwiftUI's `TabView` calls neither its selection binding nor (on iOS 26) a
/// delegate for that, so this watches touches on the tab bar itself: it notes which tab was selected when the finger went down and
/// which tab the finger lifted on, and says so when they are the same. It never takes the touch away from the bar.
struct TabRetapObserver: UIViewControllerRepresentable {
    let onRetap: (Int) -> Void

    func makeUIViewController(context: Context) -> Finder { Finder(onRetap: onRetap) }
    func updateUIViewController(_ controller: Finder, context: Context) { controller.onRetap = onRetap }

    final class Finder: UIViewController, UIGestureRecognizerDelegate {
        var onRetap: (Int) -> Void
        private var watcher: BarWatcher?

        init(onRetap: @escaping (Int) -> Void) {
            self.onRetap = onRetap
            super.init(nibName: nil, bundle: nil)
            view.isHidden = true
            view.isUserInteractionEnabled = false
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard watcher == nil, let bar = Self.findBar(in: view.window) else { return }
            let watcher = BarWatcher(bar: bar) { [weak self] index in self?.onRetap(index) }
            watcher.delegate = self
            bar.addGestureRecognizer(watcher)
            self.watcher = watcher
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        private static func findBar(in view: UIView?) -> UITabBar? {
            guard let view else { return nil }
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews { if let found = findBar(in: sub) { return found } }
            return nil
        }
    }

    /// Sees touches on the tab bar without ever claiming them.
    final class BarWatcher: UIGestureRecognizer {
        private weak var bar: UITabBar?
        private let retap: (Int) -> Void
        private var pending: Task<Void, Never>?

        init(bar: UITabBar, retap: @escaping (Int) -> Void) {
            self.bar = bar
            self.retap = retap
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        /// A touch that lands on the tab already selected is a re-tap (the selected tab cannot change under it); it counts unless the
        /// finger moves away or the touch is cancelled within a moment.
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let bar, let touch = touches.first, let started = bar.selectedItem.flatMap({ bar.items?.firstIndex(of: $0) }),
                  let count = bar.items?.count, count > 0 else { return }
            let down = touch.location(in: bar)
            let platter = Self.platter(in: bar)?.frame ?? bar.bounds
            guard platter.contains(down) else { return }
            let index = min(count - 1, max(0, Int((down.x - platter.minX) / platter.width * CGFloat(count))))
            guard index == started else { return }
            pending?.cancel()
            pending = Task { @MainActor [retap] in
                try? await Task.sleep(for: .milliseconds(120))
                if !Task.isCancelled { retap(index) }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { pending?.cancel() }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { pending?.cancel() }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

        private static func platter(in view: UIView) -> UIView? {
            for sub in view.subviews {
                if String(describing: type(of: sub)).contains("TabBarPlatter") { return sub }
                if let found = platter(in: sub) { return found }
            }
            return nil
        }
    }
}
