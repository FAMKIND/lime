//! Sign-in and account rules that lived only in Swift (LIME-400): what a new password has and lacks, the words for why talking to the backend failed, and the
//! legal pages a teacher agrees to. Moved out of Android's `OnboardingModel.kt` (`PasswordChecks`), `ConnectionProblem.kt` and `TermsAcceptance.kt` (the Kotlin
//! twins of `PasswordChecks` in `ios/Lime/Features/Onboarding/OnboardingModel.swift`, `ConnectionProblem` in `ios/Lime/Core/Network/ConnectionProblem.swift`,
//! `TermsAcceptance` in `ios/Lime/Core/Auth/TermsAcceptance.swift`). The auth HTTP service and the state machines stay with the platform. iOS keeps its Swift until LIME-133b.

/// The fewest characters a password may have.
#[uniffi::export]
pub fn password_minimum_length() -> u32 {
    10
}

/// How good a password is, in words.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PasswordStrength {
    TooShort,
    Fair,
    Good,
    Strong,
}

#[uniffi::export]
pub fn password_strength_label(strength: PasswordStrength) -> String {
    match strength {
        PasswordStrength::TooShort => "Too short",
        PasswordStrength::Fair => "Fair",
        PasswordStrength::Good => "Good",
        PasswordStrength::Strong => "Strong",
    }
    .to_owned()
}

/// What a new password has and lacks, for the screen's hint.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PasswordReport {
    pub long_enough: bool,
    /// The confirmation matches (always true when only signing in, `creating` false).
    pub matches: bool,
    pub acceptable: bool,
    pub strength: PasswordStrength,
    pub hint: String,
}

#[uniffi::export]
pub fn password_report(password: String, confirmation: String, creating: bool) -> PasswordReport {
    let length = password.chars().count();
    let min = password_minimum_length() as usize;
    let long_enough = length >= min;
    let matches = !creating || (!confirmation.is_empty() && confirmation == password);
    let strength = if !long_enough {
        PasswordStrength::TooShort
    } else {
        let mut kinds = 0;
        if password.chars().any(char::is_lowercase) {
            kinds += 1;
        }
        if password.chars().any(char::is_uppercase) {
            kinds += 1;
        }
        if password.chars().any(char::is_numeric) {
            kinds += 1;
        }
        if password.chars().any(|c| !c.is_alphabetic() && !c.is_numeric()) {
            kinds += 1;
        }
        if length >= 16 || kinds >= 3 {
            if length >= 16 && kinds >= 2 { PasswordStrength::Strong } else { PasswordStrength::Good }
        } else {
            PasswordStrength::Fair
        }
    };
    let hint = if password.is_empty() {
        format!("At least {min} characters.")
    } else if !long_enough {
        format!("{} more to go.", min - length)
    } else {
        format!("{}. A few random words make a good password.", password_strength_label(strength))
    };
    PasswordReport { long_enough, matches, acceptable: long_enough && matches, strength, hint }
}

/// Why talking to the backend failed, in words that are true. "Check your connection" is for a real connection failure only. (Which failure is which stays
/// with the platform: it knows its own errors.)
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ConnectionTrouble {
    SessionEnded,
    Offline,
    Busy,
    Server,
    Other,
}

#[uniffi::export]
pub fn connection_trouble_words(trouble: ConnectionTrouble) -> String {
    match trouble {
        ConnectionTrouble::SessionEnded => "Your session has ended. Please sign in again.",
        ConnectionTrouble::Offline => "You're offline. Check your connection and try again.",
        ConnectionTrouble::Busy => "Too many requests. Wait a minute and try again.",
        ConnectionTrouble::Server => "lime's server had a problem. Try again in a moment.",
        ConnectionTrouble::Other => "Something went wrong. Try again.",
    }
    .to_owned()
}

/// Only an ended session needs the person to do something (sign in again).
#[uniffi::export]
pub fn connection_trouble_needs_sign_in(trouble: ConnectionTrouble) -> bool {
    trouble == ConnectionTrouble::SessionEnded
}

/// The terms version a teacher agrees to at sign-up (LIME-283). Change it when the terms change in a way people must agree to again.
#[uniffi::export]
pub fn terms_current_version() -> String {
    "terms-2026-11".to_owned()
}

/// The legal pages of limemessenger.com.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LegalLinks {
    pub terms: String,
    pub privacy: String,
    pub guidelines: String,
    pub safety: String,
}

#[uniffi::export]
pub fn legal_links() -> LegalLinks {
    LegalLinks {
        terms: "https://limemessenger.com/terms".to_owned(),
        privacy: "https://limemessenger.com/privacy".to_owned(),
        guidelines: "https://limemessenger.com/guidelines".to_owned(),
        safety: "https://limemessenger.com/safety".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(p: &str, c: &str, creating: bool) -> PasswordReport {
        password_report(p.into(), c.into(), creating)
    }

    // OnboardingModelTest (the cases of iOS's PasswordChecks).
    #[test]
    fn the_hint_and_the_strength() {
        assert_eq!(report("", "", true).hint, "At least 10 characters.");
        assert_eq!(report("abcdef", "", true).hint, "4 more to go.");
        assert_eq!(report("short", "", true).strength, PasswordStrength::TooShort);
        assert_eq!(report("abcdefghij", "", true).strength, PasswordStrength::Fair);
        assert_eq!(report("Abcdefghi1", "", true).strength, PasswordStrength::Good);
        assert_eq!(report("a-long-passphrase-of-words", "", true).strength, PasswordStrength::Strong);
        assert_eq!(report("Abcdefghi1", "", true).hint, "Good. A few random words make a good password.");
    }

    #[test]
    fn a_new_password_must_be_long_enough_and_confirmed() {
        assert!(!report("abcdefghij", "abcdefghi", true).acceptable);
        assert!(report("abcdefghij", "abcdefghij", true).acceptable);
        assert!(report("abcdefghij", "", false).matches, "signing in needs no confirmation");
        assert!(!report("abcdefghij", "", true).matches);
    }

    // ConnectionProblem.swift's words.
    #[test]
    fn the_words_for_why_the_backend_failed() {
        assert_eq!(connection_trouble_words(ConnectionTrouble::SessionEnded), "Your session has ended. Please sign in again.");
        assert_eq!(connection_trouble_words(ConnectionTrouble::Offline), "You're offline. Check your connection and try again.");
        assert_eq!(connection_trouble_words(ConnectionTrouble::Busy), "Too many requests. Wait a minute and try again.");
        assert_eq!(connection_trouble_words(ConnectionTrouble::Server), "lime's server had a problem. Try again in a moment.");
        assert_eq!(connection_trouble_words(ConnectionTrouble::Other), "Something went wrong. Try again.");
        assert!(connection_trouble_needs_sign_in(ConnectionTrouble::SessionEnded));
        assert!(!connection_trouble_needs_sign_in(ConnectionTrouble::Offline));
    }

    #[test]
    fn the_terms_version_and_the_legal_pages() {
        assert_eq!(terms_current_version(), "terms-2026-11");
        let l = legal_links();
        assert_eq!((l.terms.as_str(), l.privacy.as_str()), ("https://limemessenger.com/terms", "https://limemessenger.com/privacy"));
        assert_eq!((l.guidelines.as_str(), l.safety.as_str()), ("https://limemessenger.com/guidelines", "https://limemessenger.com/safety"));
    }
}
