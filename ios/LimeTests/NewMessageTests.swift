import XCTest
@testable import Lime

@MainActor
final class NewMessageTests: XCTestCase {
    private func dm(_ name: String, request: Bool = false) -> Conversation {
        let who = Person(id: name.lowercased(), name: name)
        return Conversation(id: "dm:\(who.id)", title: name, members: [who], messages: [], isRequest: request)
    }

    func testKnownTeachersAreAcceptedDirectChatsOnly() {
        let group = Conversation(id: "g", title: "Staff", members: [Person(id: "a", name: "A"), Person(id: "b", name: "B")], messages: [])
        let known = KnownTeachers.from([dm("Lee Wong"), dm("Ada Lovelace", request: true), group])
        XCTAssertEqual(known.map(\.person.name), ["Lee Wong"], "requests and groups are not teachers you know")
    }

    func testSectionsAreSortedAToZWithOthersLastAndAccentsFiledUnderTheirLetter() {
        let known = KnownTeachers.from([dm("Zoe Adler"), dm("Éloïse Martin"), dm("ben okafor"), dm("Ada Lovelace"), dm("Ana Cruz"), dm("123 Room"), dm("Lee Wong")])
        let sections = KnownTeachers.sections(known)
        XCTAssertEqual(sections.map(\.letter), ["A", "B", "E", "L", "Z", "#"])
        XCTAssertEqual(sections[0].teachers.map(\.person.name), ["Ada Lovelace", "Ana Cruz"], "sorted inside a letter")
        XCTAssertEqual(sections[2].teachers.map(\.person.name), ["Éloïse Martin"])
        XCTAssertEqual(KnownTeachers.letter(for: "  ben"), "B")
        XCTAssertEqual(KnownTeachers.letter(for: "😀"), "#")
        XCTAssertEqual(KnownTeachers.rail.count, 27)
        XCTAssertEqual(KnownTeachers.rail.first, "A")
        XCTAssertEqual(KnownTeachers.rail.last, "#")
    }

    func testTypingFiltersTheListLive() {
        let known = KnownTeachers.from([dm("Lee Wong"), dm("Leah Park"), dm("Ada Lovelace"), dm("Sam Park")])
        XCTAssertEqual(KnownTeachers.sections(known, filter: "le").flatMap(\.teachers).map(\.person.name), ["Leah Park", "Lee Wong"])
        XCTAssertEqual(KnownTeachers.sections(known, filter: "park").flatMap(\.teachers).map(\.person.name), ["Leah Park", "Sam Park"], "any word of the name")
        XCTAssertEqual(KnownTeachers.sections(known, filter: "lee w").flatMap(\.teachers).map(\.person.name), ["Lee Wong"])
        XCTAssertTrue(KnownTeachers.sections(known, filter: "zebra").isEmpty)
        XCTAssertEqual(KnownTeachers.sections(known, filter: "  ").flatMap(\.teachers).count, 4, "blank shows everyone")
    }

    func testLookupFieldsAcceptOnlyWholeUsernamesAndEmails() {
        XCTAssertFalse(LookupKind.username.accepts(""), "Next is off until there is input")
        XCTAssertFalse(LookupKind.username.accepts("gr"), "too short for a username")
        XCTAssertTrue(LookupKind.username.accepts("grace.h"))
        XCTAssertTrue(LookupKind.username.accepts("@grace.h"))
        XCTAssertFalse(LookupKind.username.accepts("grace@school.org"), "an email is not a username")
        XCTAssertTrue(LookupKind.email.accepts("grace@school.org"))
        XCTAssertFalse(LookupKind.email.accepts("grace"))
        XCTAssertFalse(LookupKind.email.accepts("grace@school"))
        XCTAssertEqual(LookupKind.username.query(" @grace.h "), "grace.h", "the server gets the bare username")
        XCTAssertEqual(LookupKind.email.query(" grace@school.org "), "grace@school.org")
    }

    func testAnExactLookupByUsernameAndByEmailFindsOrReportsNobody() async {
        let store = ConversationStore()
        store.loadDemo()
        let byName = TeacherLookup()
        await byName.run("grace.h", store: store)
        guard case .found(let person) = byName.state else { return XCTFail("a username match: \(byName.state)") }
        XCTAssertEqual(person.displayName, "Grace Hopper")
        let byEmail = TeacherLookup()
        await byEmail.run("grace@navy.example", store: store)
        guard case .found = byEmail.state else { return XCTFail("an email match: \(byEmail.state)") }
        let nobody = TeacherLookup()
        await nobody.run("nobody.here", store: store)
        XCTAssertEqual(nobody.state, .nobody)
        nobody.reset()
        XCTAssertEqual(nobody.state, .idle)
    }
}
