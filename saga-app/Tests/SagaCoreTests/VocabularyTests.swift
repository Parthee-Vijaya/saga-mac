import Foundation
import Testing
@testable import Saga

@Suite("VocabularyPostProcessor")
struct VocabularyPostProcessorTests {
    let processor = VocabularyPostProcessor()

    @Test("Empty entries returns input unchanged")
    func emptyEntries() {
        let result = processor.apply("Hej verden", entries: [])
        #expect(result == "Hej verden")
    }

    @Test("Single replacement applied case-insensitively")
    func singleReplacement() {
        let entry = VocabularyEntry(pattern: "x-code-jen", replacement: "xcodegen")
        let result = processor.apply("Jeg bruger x-code-jen til build", entries: [entry])
        #expect(result == "Jeg bruger xcodegen til build")
    }

    @Test("Whole-word matching avoids substring false positives")
    func wholeWordMatch() {
        let entry = VocabularyEntry(pattern: "ged", replacement: "kat", wholeWord: true)
        let result = processor.apply("Den ged blev hjemløs i Geddesgade", entries: [entry])
        // "ged" should be replaced but "Geddesgade" left alone
        #expect(result.contains("Den kat blev hjemløs"))
        #expect(result.contains("Geddesgade"))
    }

    @Test("Substring match when wholeWord disabled")
    func substringMatch() {
        let entry = VocabularyEntry(pattern: "ged", replacement: "kat", wholeWord: false)
        let result = processor.apply("Geddesgade", entries: [entry])
        #expect(result.contains("kat"))
    }

    @Test("Case sensitivity respected when enabled")
    func caseSensitive() {
        let entry = VocabularyEntry(pattern: "API", replacement: "Application Programming Interface", caseSensitive: true)
        let result = processor.apply("API kaldes også api i daglig tale", entries: [entry])
        #expect(result.contains("Application Programming Interface"))
        #expect(result.contains("api i daglig tale"))
    }

    @Test("Disabled entries are skipped")
    func disabledSkipped() {
        let entry = VocabularyEntry(pattern: "saga", replacement: "Saga", enabled: false)
        let result = processor.apply("saga er fed", entries: [entry])
        #expect(result == "saga er fed")
    }

    @Test("Meaningless entries (empty or pattern == replacement) are skipped")
    func meaninglessSkipped() {
        let empty = VocabularyEntry(pattern: "", replacement: "")
        let identity = VocabularyEntry(pattern: "ged", replacement: "ged")
        let result = processor.apply("ged er ged", entries: [empty, identity])
        #expect(result == "ged er ged")
    }

    @Test("Multiple entries applied in sequence")
    func multipleEntries() {
        let entries = [
            VocabularyEntry(pattern: "parti", replacement: "Parthee"),
            VocabularyEntry(pattern: "saga", replacement: "Saga"),
        ]
        let result = processor.apply("parti laver saga", entries: entries)
        #expect(result == "Parthee laver Saga")
    }

    @Test("Special regex characters in pattern are escaped")
    func regexCharsEscaped() {
        let entry = VocabularyEntry(pattern: "C++", replacement: "C plus plus", wholeWord: false)
        let result = processor.apply("C++ er svært", entries: [entry])
        #expect(result.contains("C plus plus"))
    }

    @Test("Special regex characters in replacement are escaped")
    func replacementCharsEscaped() {
        let entry = VocabularyEntry(pattern: "money", replacement: "$$$ profit", wholeWord: false)
        let result = processor.apply("more money please", entries: [entry])
        #expect(result.contains("$$$ profit"))
    }

    @Test("Danish characters in pattern handled correctly")
    func danishCharsInPattern() {
        let entry = VocabularyEntry(pattern: "øl", replacement: "beer")
        let result = processor.apply("Jeg vil have en øl", entries: [entry])
        #expect(result == "Jeg vil have en beer")
    }
}

@Suite("VocabularyEntry")
struct VocabularyEntryTests {

    @Test("isMeaningful: empty pattern is not meaningful")
    func emptyPatternNotMeaningful() {
        let entry = VocabularyEntry(pattern: "", replacement: "x")
        #expect(!entry.isMeaningful)
    }

    @Test("isMeaningful: pattern equal to replacement is no-op")
    func identityNotMeaningful() {
        let entry = VocabularyEntry(pattern: "ged", replacement: "ged")
        #expect(!entry.isMeaningful)
    }

    @Test("isMeaningful: pattern with whitespace-only difference is no-op")
    func whitespaceOnlyDifference() {
        let entry = VocabularyEntry(pattern: " ged ", replacement: "ged")
        #expect(!entry.isMeaningful)
    }

    @Test("isMeaningful: real replacement is meaningful")
    func realReplacementMeaningful() {
        let entry = VocabularyEntry(pattern: "ged", replacement: "kat")
        #expect(entry.isMeaningful)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = VocabularyEntry(
            pattern: "test",
            replacement: "TEST",
            caseSensitive: true,
            wholeWord: false,
            enabled: false,
            notes: "for unit-test"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VocabularyEntry.self, from: data)
        #expect(decoded == original)
    }
}
