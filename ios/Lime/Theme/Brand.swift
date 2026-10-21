import Foundation

/// The brand, in one place (LIME-178). The product is written **lime**, lowercase, wherever a teacher can see it.
enum Brand {
    /// The legal line. It is written now and stays hidden until both companies exist (never mention 501(c)(3) until the IRS grants it).
    static let legalLine = "lime is made by Lime Messenger LLC, owned by Lime Messenger Inc, a nonprofit."
    /// Turn this on (and the matching switches in `invite-site/` and `supabase/templates/code.html`) when the user confirms both companies exist.
    static let showLegalLine = false
}
