import Foundation

/// Where the app's backend is. The values are generated at project-generation time (see
/// `ios/generate.sh`); both are public by design (the anon key ships inside apps). A Debug build can
/// point at the local Supabase stack with the launch arguments below.
struct BackendConfig: Sendable, Equatable {
    let url: URL
    let apiKey: String

    /// nil when the project was generated without a backend.
    static var current: BackendConfig? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-lime-api-url"), index + 1 < arguments.count,
           let keyIndex = arguments.firstIndex(of: "-lime-api-key"), keyIndex + 1 < arguments.count,
           let url = URL(string: arguments[index + 1]) {
            return BackendConfig(url: url, apiKey: arguments[keyIndex + 1])
        }
        #endif
        guard let string = GeneratedBackend.url, let url = URL(string: string), let key = GeneratedBackend.apiKey else { return nil }
        return BackendConfig(url: url, apiKey: key)
    }
}
