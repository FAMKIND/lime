#if DEBUG
import Foundation

/// Debug builds only: `-lime-onboarding-screen <name>` opens the flow straight at one screen with
/// canned content (for screenshots). Names: welcome, identifier, identifier-valid, identifier-phone, confirm-email,
/// confirm-username, confirm-unknown, code, password-create, password-signin, forgot-code,
/// forgot-password, profile.
@MainActor
enum DebugOnboarding {
    static func apply(to model: OnboardingModel) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-lime-onboarding-screen"), index + 1 < arguments.count else { return }
        model.debugShow(arguments[index + 1])
    }
}

extension OnboardingModel {
    func debugShow(_ name: String) {
        switch name {
        case "welcome": break
        case "identifier": start()
        case "identifier-valid":
            start()
            identifier = "teacher@famkind.com"
        case "identifier-phone":
            start()
            identifier = "+1 555 010 0199"
        case "confirm-email":
            start()
            identifier = "new.teacher@example.com"
            Task { await submitIdentifier() }
        case "confirm-username":
            start()
            identifier = "@s.park"
            Task { await submitIdentifier() }
        case "confirm-unknown":
            start()
            identifier = "nobody"
            Task { await submitIdentifier() }
        case "code":
            start()
            identifier = "new.teacher@example.com"
            Task { await submitIdentifier(); await confirmIdentifier() }
        case "password-create":
            start()
            identifier = "new.teacher@example.com"
            Task {
                await submitIdentifier(); await confirmIdentifier()
                code = FakeAuthService.code
                await submitCode()
                password = "short"
            }
        case "password-signin":
            start()
            identifier = "s.park"
            Task { await submitIdentifier(); await confirmIdentifier() }
        case "forgot-code":
            start()
            identifier = "s.park"
            Task { await submitIdentifier(); await confirmIdentifier(); await forgotPassword() }
        case "forgot-password":
            start()
            identifier = "s.park"
            Task {
                await submitIdentifier(); await confirmIdentifier(); await forgotPassword()
                code = FakeAuthService.code
                await submitCode()
                password = "a long enough one"
                confirmPassword = "a long enough one"
            }
        case "profile":
            start()
            identifier = "new.teacher@example.com"
            Task {
                await submitIdentifier(); await confirmIdentifier()
                code = FakeAuthService.code
                await submitCode()
                password = FakeAuthService.password
                confirmPassword = FakeAuthService.password
                await submitPassword()
            }
        default: break
        }
    }
}
#endif
