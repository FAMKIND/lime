import Foundation
import UIKit

/// LIME-259: one kind of band. Before real bands (LIME-254) a teacher made a "band" by renaming the profile posting space (their oldest jam); that space is
/// always the teacher now. This runs once on the owner's phone after the update: if the space is named something other than the teacher, a real band is made with
/// its name, about, tags, picture, colour and cover, and the space is named for the teacher again. Posts already made stay in the space (under the teacher's name);
/// subscribers stay subscribed to the teacher; nobody follows the new band without choosing it.
extension ConversationStore {
    private var cleanupKey: String { "lime.bandCleanup259.\(meProvider().id)" }

    /// The cleanup's record: the new band's id once it is made, "done" at the end. A demo run keeps it in memory, so every test starts clean.
    private var cleanupState: String? {
        get {
            #if DEBUG
            if isDemo { return demoCleanupState }
            #endif
            return UserDefaults.standard.string(forKey: cleanupKey)
        }
        set {
            #if DEBUG
            if isDemo { demoCleanupState = newValue; return }
            #endif
            UserDefaults.standard.set(newValue, forKey: cleanupKey)
        }
    }

    /// Set once the band exists: its page says, once, what happened.
    func setBandNote(_ jamID: String, _ on: Bool) {
        #if DEBUG
        if isDemo { if on { demoBandNotes.insert(jamID) } else { demoBandNotes.remove(jamID) }; return }
        #endif
        UserDefaults.standard.set(on, forKey: "lime.bandCleanupNote.\(jamID)")
    }

    /// Reads the note and clears it: it is shown once.
    func takeBandNote(_ jamID: String) -> Bool {
        #if DEBUG
        if isDemo { return demoBandNotes.remove(jamID) != nil }
        #endif
        let key = "lime.bandCleanupNote.\(jamID)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        return UserDefaults.standard.bool(forKey: key)
    }

    func cleanUpOldBands() async {
        guard jamsLoaded, !cleaningBands, let old = myOwnJam else { return }
        let name = meProvider().name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let state = cleanupState
        if state == "done" { return }
        // Already named for the teacher: nothing old-style here (and it never runs later, when a name could change).
        if old.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased() { cleanupState = "done"; return }
        cleaningBands = true
        defer { cleaningBands = false }

        // The band, made once: its id is recorded at once, so a retry after a failure does not make a second one.
        var bandID = state.flatMap { id in jamsMine.contains { $0.jamId == id } ? id : nil }
        let picture = await heldJamPicture(old.jamId)
        if bandID == nil {
            bandID = await createPublication(title: old.title, about: old.about, topics: old.topics, picture: picture, demoID: "demo-band-\(old.jamId)")
            guard let made = bandID else { return }
            cleanupState = made
        }
        guard let band = bandID else { return }

        // The colour and cover go with it.
        let style = await heldJamStyle(old.jamId)
        if let tone = style.tone { await setJamTone(band, tone: tone) }
        if let cover = style.cover { await setJamCover(band, jpeg: cover) }

        // The space is the teacher again, and no longer carries the band's look.
        guard await editJam(old.jamId, title: String(name.prefix(60)), about: old.about, topics: old.topics) else { return }
        if picture != nil { _ = await removeJamPicture(old.jamId) }
        if style.cover != nil { await removeJamCover(old.jamId) }
        if style.tone != nil { await setJamTone(old.jamId, tone: nil) }
        setBandNote(band, true)
        cleanupState = "done"
    }

    /// The picture this phone holds for a jam, as JPEG bytes.
    private func heldJamPicture(_ jamID: String) async -> Data? {
        #if DEBUG
        if isDemo { return AvatarCache.shared.image(for: Self.jamPictureKey(jamID))?.jpegData(compressionQuality: 0.8) }
        #endif
        guard let core else { return nil }
        return await Task.detached { (try? core.jamPicture(jamId: jamID)) ?? nil }.value
    }

    private func heldJamStyle(_ jamID: String) async -> (tone: Int?, cover: Data?) {
        #if DEBUG
        if isDemo { return (jamTones[jamID], AvatarCache.shared.image(for: Self.jamCoverKey(jamID))?.jpegData(compressionQuality: 0.8)) }
        #endif
        guard let core else { return (nil, nil) }
        let held = await Task.detached { ((try? core.jamTone(jamId: jamID)) ?? nil, (try? core.jamCover(jamId: jamID)) ?? nil) }.value
        return (held.0.map { Int($0) }, held.1)
    }
}
