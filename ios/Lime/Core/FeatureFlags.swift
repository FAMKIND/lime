import Foundation

/// Features that are built but not yet for everyone.
enum FeatureFlags {
    /// Co-editing (LIME-233): the article editor works on a shared draft. On in Debug; in Release it needs the `coedit` default switched on.
    static var coedit: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-lime-no-coedit")
        #else
        return UserDefaults.standard.bool(forKey: "coedit")
        #endif
    }
}
