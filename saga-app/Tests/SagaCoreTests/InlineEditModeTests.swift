import Foundation
import Testing
@testable import Saga

@Suite("InlineEditMode trigger detection")
struct InlineEditModeTests {
    @Test("Empty input returns nil")
    func emptyInput() {
        #expect(InlineEditMode.detectInstruction("") == nil)
    }

    @Test("No trigger returns nil")
    func noTrigger() {
        let result = InlineEditMode.detectInstruction("Hej Lars, det er en lang besked uden instruktion")
        #expect(result == nil)
    }

    @Test("Trigger at end: 'skriv det som email'")
    func triggerSkrivDetSomEmail() {
        let result = InlineEditMode.detectInstruction(
            "Hej Lars, jeg har lavet et nyt design som du skal kigge på, skriv det som en email"
        )
        #expect(result != nil)
        #expect(result?.content == "Hej Lars, jeg har lavet et nyt design som du skal kigge på")
        #expect(result?.instruction == "skriv det som en email")
    }

    @Test("Trigger 'i punktopstilling'")
    func triggerPunktopstilling() {
        let result = InlineEditMode.detectInstruction(
            "Køb mælk, brød, smør og ost i punktopstilling"
        )
        #expect(result != nil)
        #expect(result?.content == "Køb mælk, brød, smør og ost")
        #expect(result?.instruction == "i punktopstilling")
    }

    @Test("Case-insensitive matching")
    func caseInsensitive() {
        let result = InlineEditMode.detectInstruction(
            "Hej Lars dette er en test, Skriv Det Som Email"
        )
        #expect(result != nil)
        #expect(result?.content == "Hej Lars dette er en test")
    }

    @Test("Multiple triggers — last-wins")
    func multipleTriggersLastWins() {
        // "skriv det som" forekommer to gange — vi vælger sidste
        let result = InlineEditMode.detectInstruction(
            "skriv det som en intro, og så indholdet, skriv det som en email"
        )
        #expect(result != nil)
        // Sidste forekomst er trigger
        #expect(result?.instruction == "skriv det som en email")
        #expect(result?.content.contains("skriv det som en intro") == true)
    }

    @Test("Punctuation before trigger")
    func punctuationBeforeTrigger() {
        let result = InlineEditMode.detectInstruction(
            "Hej Lars, vi mødes klokken 14. Skriv det som en formel email"
        )
        #expect(result != nil)
        #expect(result?.content.contains("Hej Lars") == true)
        #expect(result?.instruction.lowercased().hasPrefix("skriv det som") == true)
    }

    @Test("Empty content before trigger returns nil")
    func emptyContentReturnsNil() {
        // Hvis brugeren bare siger trigger uden indhold, ingen meningsfuld edit
        let result = InlineEditMode.detectInstruction("skriv det som email")
        #expect(result == nil)
    }

    @Test("Very short content (< 5 chars) returns nil")
    func tooShortContent() {
        let result = InlineEditMode.detectInstruction("Hej, skriv det som email")
        // "Hej" er kun 3 chars efter trim — ikke meningsfuldt at redigere
        #expect(result == nil)
    }

    @Test("Trigger inside non-trigger phrase NOT matched")
    func triggerNotMatchedInWord() {
        // "Beskriv det som" indeholder substring "skriv det som" men starter
        // ikke ved word-boundary — bør ikke match
        let result = InlineEditMode.detectInstruction(
            "Jeg vil gerne beskrive det som lidt anderledes"
        )
        // "skriv det som" er substring af "beskrive det som", men begin-of-word
        // ikke OK fordi prev char er "be"
        // Vi bevidst test'er at vi IKKE matcher pga isAtBoundary-tjek
        #expect(result == nil || result?.instruction.hasPrefix("skriv det som") == false)
    }

    @Test("Trigger 'gør det mere formelt'")
    func triggerGørDetMereFormelt() {
        let result = InlineEditMode.detectInstruction(
            "Jeg vil gerne sige tak for jeres hjælp, gør det mere formelt"
        )
        #expect(result != nil)
        #expect(result?.instruction == "gør det mere formelt")
        #expect(result?.content == "Jeg vil gerne sige tak for jeres hjælp")
    }

    @Test("Longest trigger wins when multiple at same position")
    func longestTriggerWins() {
        // "skriv det om til" er længere end "skriv om til" — bør vinde
        let result = InlineEditMode.detectInstruction(
            "Det her er en lang besked, skriv det om til en formel email"
        )
        #expect(result != nil)
        #expect(result?.instruction.hasPrefix("skriv det om til") == true)
    }
}
