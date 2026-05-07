import Foundation
import Testing
@testable import Saga

@Suite("SnippetExpander")
struct SnippetExpanderTests {
    let expander = SnippetExpander()

    @Test("Empty entries returns input unchanged")
    func emptyEntries() {
        #expect(expander.apply("Hej verden", entries: []) == "Hej verden")
    }

    @Test("Single snippet expansion at start")
    func expansionAtStart() {
        let snippet = Snippet(trigger: "min sig", expansion: "Med venlig hilsen")
        let result = expander.apply("min sig.", entries: [snippet])
        #expect(result == "Med venlig hilsen.")
    }

    @Test("Single snippet expansion in middle")
    func expansionInMiddle() {
        let snippet = Snippet(trigger: "min mail", expansion: "test@example.com")
        let result = expander.apply("Skriv til min mail tak", entries: [snippet])
        #expect(result == "Skriv til test@example.com tak")
    }

    @Test("Multi-line expansion preserves newlines")
    func multilineExpansion() {
        let snippet = Snippet(
            trigger: "min sig",
            expansion: "Med venlig hilsen,\nParthee Vijaya"
        )
        let result = expander.apply("Hej. min sig", entries: [snippet])
        #expect(result.contains("Med venlig hilsen,\nParthee Vijaya"))
    }

    @Test("Case-insensitive matching by default")
    func caseInsensitive() {
        let snippet = Snippet(trigger: "saga repo", expansion: "https://github.com/x/y")
        let result = expander.apply("Se SAGA REPO her.", entries: [snippet])
        #expect(result == "Se https://github.com/x/y here.".replacingOccurrences(of: "here", with: "her"))
    }

    @Test("Case-sensitive matching when enabled")
    func caseSensitive() {
        let snippet = Snippet(
            trigger: "API",
            expansion: "Application Programming Interface",
            caseSensitive: true
        )
        let result = expander.apply("Min api og din API", entries: [snippet])
        // "api" må IKKE matche, kun "API"
        #expect(result == "Min api og din Application Programming Interface")
    }

    @Test("Trigger som substring matcher IKKE")
    func notMatchSubstring() {
        let snippet = Snippet(trigger: "min", expansion: "MIN")
        // "min" som substring af "minder" må ikke matche
        let result = expander.apply("Det minder om noget", entries: [snippet])
        #expect(result == "Det minder om noget")
    }

    @Test("Disabled snippet does not apply")
    func disabledSnippet() {
        let snippet = Snippet(
            trigger: "min sig",
            expansion: "Should not appear",
            enabled: false
        )
        let result = expander.apply("min sig.", entries: [snippet])
        #expect(result == "min sig.")
    }

    @Test("isMeaningful blocks empty trigger")
    func emptyTriggerNotMeaningful() {
        let snippet = Snippet(trigger: "", expansion: "anything")
        #expect(snippet.isMeaningful == false)
    }

    @Test("isMeaningful blocks trigger == expansion")
    func sameAsExpansion() {
        let snippet = Snippet(trigger: "hej", expansion: "hej")
        #expect(snippet.isMeaningful == false)
    }

    @Test("Multiple snippets applied in order")
    func multipleSnippets() {
        let s1 = Snippet(trigger: "min sig", expansion: "Hilsen Parthee")
        let s2 = Snippet(trigger: "min mail", expansion: "test@x.com")
        let result = expander.apply(
            "Hej. min sig og min mail.",
            entries: [s1, s2]
        )
        #expect(result == "Hej. Hilsen Parthee og test@x.com.")
    }

    @Test("Special regex chars in expansion are escaped")
    func regexCharsInExpansion() {
        // Replacement-template skal escape $1 osv. så de ikke fortolkes
        let snippet = Snippet(trigger: "ref", expansion: "$1.50 per use")
        let result = expander.apply("Ref tak", entries: [snippet])
        #expect(result == "$1.50 per use tak")
    }
}
