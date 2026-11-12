import Foundation

/// Features that are built but not yet for everyone.
enum FeatureFlags {
    /// Co-editing (LIME-233): the article editor works on a shared draft. **On** in Debug and in Release (LIME-320). Two local off switches, for emergencies: the
    /// launch argument `-lime-no-coedit` (Debug) and the `coedit_off` default (any build). The old `coedit` default, which used to switch it on in Release, is ignored.
    static var coedit: Bool {
        #if DEBUG
        let launchOff = ProcessInfo.processInfo.arguments.contains("-lime-no-coedit")
        #else
        let launchOff = false
        #endif
        return coeditEnabled(launchOff: launchOff, userOff: UserDefaults.standard.bool(forKey: "coedit_off"))
    }

    /// The rule as a pure function of the two switches (a test pins it).
    static func coeditEnabled(launchOff: Bool, userOff: Bool) -> Bool { !launchOff && !userOff }
}
