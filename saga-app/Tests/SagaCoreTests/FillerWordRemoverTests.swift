import Foundation
import Testing
@testable import Saga

@Suite("FillerWordRemover")
struct FillerWordRemoverTests {
    let remover = FillerWordRemover()

    @Test("Empty string returns empty")
    func emptyString() {
        #expect(remover.apply("") == "")
    }

    @Test("Strip 'øh' from middle")
    func stripØhFromMiddle() {
        let result = remover.apply("Hej øh jeg vil have kaffe")
        #expect(result == "Hej jeg vil have kaffe")
    }

    @Test("Strip 'øhm' from start")
    func stripØhmFromStart() {
        let result = remover.apply("Øhm, jeg er på vej")
        #expect(result == "Jeg er på vej")
    }

    @Test("Strip multiple safe fillers")
    func stripMultipleSafeFillers() {
        let result = remover.apply("Øh, øhm, jeg vil sige tak")
        #expect(result == "Jeg vil sige tak")
    }

    @Test("Case-insensitive matching")
    func caseInsensitive() {
        let result = remover.apply("ØH ja, og ØHM nej")
        #expect(result == "Ja, og nej")
    }

    @Test("Preserve 'ja' alone — not a filler")
    func preserveJa() {
        let result = remover.apply("Ja, det vil jeg gerne")
        #expect(result == "Ja, det vil jeg gerne")
    }

    @Test("Preserve 'ikke' as negation")
    func preserveIkkeAsNegation() {
        let result = remover.apply("Det skal ikke være sådan")
        #expect(result == "Det skal ikke være sådan")
    }

    @Test("Strip 'altså' as standalone interjection at start")
    func stripAltsåAtStart() {
        let result = remover.apply("Altså, jeg vil sige det er fint")
        #expect(result == "Jeg vil sige det er fint")
    }

    @Test("Preserve 'altså' inside phrase")
    func preserveAltsåInPhrase() {
        // "der er altså ikke noget" — "altså" indgår i fast frase, må ikke strippes
        let result = remover.apply("Der er altså ikke noget at gøre")
        #expect(result == "Der er altså ikke noget at gøre")
    }

    @Test("Strip 'ligesom' between commas")
    func stripLigesomBetweenCommas() {
        let result = remover.apply("Det var, ligesom, mærkeligt")
        #expect(result == "Det var, mærkeligt")
    }

    @Test("Trailing punctuation preserved")
    func trailingPunctuation() {
        let result = remover.apply("Jeg vil øh.")
        #expect(result == "Jeg vil.")
    }

    @Test("Question mark preserved")
    func questionMark() {
        let result = remover.apply("Hvad skal vi øh gøre?")
        #expect(result == "Hvad skal vi gøre?")
    }

    @Test("Multiple spaces collapsed")
    func multipleSpacesCollapsed() {
        let result = remover.apply("og  ,  så  videre")
        #expect(result == "Og, så videre")
    }

    @Test("Custom fillers via extraFillers")
    func customFillers() {
        let custom = FillerWordRemover(extraFillers: ["nemlig"])
        let result = custom.apply("Det er nemlig fint")
        #expect(result == "Det er fint")
    }

    @Test("Only-fillers input strips down to empty-ish")
    func onlyFillers() {
        let result = remover.apply("Øh, øhm, eh")
        // Should strip everything down to empty or near-empty
        #expect(result.isEmpty || result == ".")
    }

    @Test("Long sentence with multiple filler types")
    func longSentenceWithFillers() {
        let result = remover.apply("Altså, øh, jeg ville bare øhm sige at jeg er, ligesom, klar nu")
        let lower = result.lowercased()
        // Forventet: alle fillers strippet, struktur bevaret
        #expect(!lower.contains("øh"))
        #expect(!lower.contains("øhm"))
        #expect(!lower.hasPrefix("altså"))
        #expect(lower.contains("jeg ville bare sige at jeg er"))
        #expect(lower.contains("klar nu"))
    }
}
