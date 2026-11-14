#if DEBUG
import Foundation

/// Debug only (a test aid): signs in as Ada Mac with tokens `mac/run.sh` left in this app's container. The file lists the only user ids this
/// app accepts (the three Mac test accounts); any other account is refused. The tokens go through the same session code iOS uses
/// (`AccountSession.completeSignIn`: Keychain, device registration). The file is deleted once read.
enum MacTestAccount {
    static var handoverURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("lime-test-account.json")
    }

    /// At launch (`-lime-use-test-account`, as `mac/run.sh` opens the app): when tokens were handed over, they replace whatever session the app
    /// kept. Each `run.sh` makes fresh sessions for the test accounts, which ends the old one on the server, so the saved session is stale.
    @MainActor
    static func replaceSessionIfHandedOver(session: AccountSession) async {
        guard ProcessInfo.processInfo.arguments.contains("-lime-use-test-account"),
              let url = handoverURL, FileManager.default.fileExists(atPath: url.path) else { return }
        if session.phase == .signedIn { await session.endSession() }   // keeps this account's chats and keys on the Mac
        _ = await signIn(session: session)
    }

    /// Returns a message to show when it did not work, nil when signed in.
    @MainActor
    static func signIn(session: AccountSession) async -> String? {
        guard let url = handoverURL, let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let allowed = root["allowed_user_ids"] as? [String],
              let account = root["account"] as? [String: Any],
              let userID = account["user_id"] as? String,
              let access = account["access_token"] as? String,
              let refresh = account["refresh_token"] as? String
        else { return "No test account was handed over. Run mac/run.sh." }
        guard allowed.contains(userID) else { return "That account is not one of the Mac test accounts." }
        try? FileManager.default.removeItem(at: url)
        let expires = (account["expires_at"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 + 3000
        let tokens = AuthTokens(accessToken: access, refreshToken: refresh, expiresAt: Date(timeIntervalSince1970: expires), userID: userID)
        let profile = Profile(displayName: account["display_name"] as? String ?? "Ada Mac", username: account["username"] as? String, school: nil, maskedEmail: nil)
        await session.completeSignIn(tokens: tokens, profile: profile)
        return nil
    }
}
#endif
