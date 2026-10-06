import Foundation

/// The sample conversations now live in LimeCore (`core/src/store/sample.rs`) and are read from
/// the encrypted store. What is left here is the signed-in user's placeholder profile, until
/// accounts exist.
enum SampleData {
    static let me = Person(id: "me", name: "Shem Rajoon", tone: 4)
}
