import Testing
@testable import Saga

@Suite("EditMode trigger parsing")
struct EditModeTriggerTests {

    @Test("ret: trigger matches and extracts instruction")
    func retTrigger() {
        let result = EditMode.matches("ret: gør den her sætning mere formel")
        #expect(result.matched)
        #expect(result.instruction == "gør den her sætning mere formel")
    }

    @Test("rewrite: trigger matches in English")
    func rewriteTrigger() {
        let result = EditMode.matches("rewrite: make this shorter")
        #expect(result.matched)
        #expect(result.instruction == "make this shorter")
    }

    @Test("redigér: with Danish characters")
    func redigerTrigger() {
        let result = EditMode.matches("redigér: tilføj punktum")
        #expect(result.matched)
        #expect(result.instruction == "tilføj punktum")
    }

    @Test("Trailing punctuation stripped from instruction")
    func trailingPunctuation() {
        let result = EditMode.matches("ret:    ,. gør kortere   ")
        #expect(result.matched)
        // Whitespace and leading punctuation cleaned
        #expect(result.instruction.trimmingCharacters(in: .whitespaces) == "gør kortere")
    }

    @Test("No trigger means no match")
    func noTrigger() {
        let result = EditMode.matches("dette er bare en almindelig sætning")
        #expect(!result.matched)
    }

    @Test("Trigger must be at start, not in the middle")
    func triggerOnlyAtStart() {
        let result = EditMode.matches("jeg vil ret: ikke gøre det her")
        #expect(!result.matched)
    }

    @Test("Case-insensitive matching")
    func caseInsensitive() {
        let result = EditMode.matches("RET: gør formelt")
        #expect(result.matched)
    }
}
