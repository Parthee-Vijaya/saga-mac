import Foundation
import Testing
@testable import Saga

@Suite("CalendarMode trigger parsing")
struct CalendarModeTriggerTests {

    @Test("'book møde' matches and extracts payload")
    func bookMode() {
        let result = CalendarMode.matches("book møde med Lars i morgen kl 14 til 15")
        #expect(result.matched)
        // 'møde med' har special-handling — den prepender 'møde med' tilbage så LLM ser deltagerne
        // 'book møde' har ikke special-handling, så payload er den rå rest
        #expect(result.payload.contains("Lars"))
    }

    @Test("'book et møde' matches")
    func bookEtMode() {
        let result = CalendarMode.matches("book et møde med Anna torsdag kl 10")
        #expect(result.matched)
    }

    @Test("'møde med' matches og bevarer 'med X' i payload")
    func modeMedTrigger() {
        let result = CalendarMode.matches("møde med Lars i morgen kl 14")
        #expect(result.matched)
        // Special: "møde med" prependes tilbage så LLM ser "med Lars" til attendees
        #expect(result.payload.contains("med Lars"))
    }

    @Test("'kalender:' matches")
    func kalenderTrigger() {
        let result = CalendarMode.matches("kalender: Q3-status fredag kl 9")
        #expect(result.matched)
        #expect(result.payload.contains("Q3-status"))
    }

    @Test("'schedule meeting' matches engelsk trigger")
    func scheduleMeeting() {
        let result = CalendarMode.matches("schedule meeting with Anna tomorrow 10am")
        #expect(result.matched)
    }

    @Test("Tekst uden trigger matcher ikke")
    func noMatch() {
        let result = CalendarMode.matches("hej, jeg vil gerne sige tak for mødet i går")
        #expect(!result.matched)
    }

    @Test("Tom string matcher ikke")
    func emptyString() {
        let result = CalendarMode.matches("")
        #expect(!result.matched)
    }

    @Test("Whitespace strippes inden trigger-match")
    func leadingWhitespace() {
        let result = CalendarMode.matches("   book møde med Lars torsdag kl 14")
        #expect(result.matched)
    }

    @Test("Case-insensitiv matching")
    func caseInsensitive() {
        let result = CalendarMode.matches("BOOK MØDE med Anna torsdag")
        #expect(result.matched)
    }
}

@Suite("CalendarMode LLM response parsing")
struct CalendarModeLLMParsingTests {

    @Test("Valid JSON med start + end + attendees")
    func validJSON() throws {
        let json = """
        {"title":"Q3-status","start_iso8601":"2026-05-08T14:00","end_iso8601":"2026-05-08T15:00","attendees":["Lars"],"notes":"diskuter Q3-tal"}
        """
        let parsed = try CalendarMode.parseLLMResponse(json)
        #expect(parsed.title == "Q3-status")
        #expect(parsed.attendees == ["Lars"])
        #expect(parsed.notes == "diskuter Q3-tal")
        // start skal være før end
        #expect(parsed.end > parsed.start)
        // 60 min varighed
        #expect(parsed.end.timeIntervalSince(parsed.start) == 3600)
    }

    @Test("Manglende end_iso8601 → default 60 min varighed")
    func missingEndDate() throws {
        let json = """
        {"title":"Standup","start_iso8601":"2026-05-08T09:00","attendees":[],"notes":""}
        """
        let parsed = try CalendarMode.parseLLMResponse(json)
        #expect(parsed.end.timeIntervalSince(parsed.start) == 3600)
    }

    @Test("Markdown-fences strippes inden parse")
    func markdownFences() throws {
        let json = """
        ```json
        {"title":"1:1","start_iso8601":"2026-05-08T13:00","end_iso8601":"2026-05-08T13:30","attendees":["Anna"],"notes":""}
        ```
        """
        let parsed = try CalendarMode.parseLLMResponse(json)
        #expect(parsed.title == "1:1")
        #expect(parsed.attendees == ["Anna"])
    }

    @Test("Error-shape kastes som CalendarError.parseFailed")
    func errorShape() {
        let json = """
        {"error":"kunne ikke forstå tidspunkt"}
        """
        #expect(throws: CalendarError.self) {
            _ = try CalendarMode.parseLLMResponse(json)
        }
    }

    @Test("Ugyldigt timestamp kastes")
    func invalidTimestamp() {
        let json = """
        {"title":"X","start_iso8601":"ikke-en-dato","attendees":[]}
        """
        #expect(throws: CalendarError.self) {
            _ = try CalendarMode.parseLLMResponse(json)
        }
    }

    @Test("Date uden 'T' separator parses også")
    func spaceSeparator() throws {
        let json = """
        {"title":"X","start_iso8601":"2026-05-08 14:00","end_iso8601":"2026-05-08 15:00","attendees":[]}
        """
        let parsed = try CalendarMode.parseLLMResponse(json)
        #expect(parsed.end.timeIntervalSince(parsed.start) == 3600)
    }

    @Test("Tom attendees-array tillades")
    func emptyAttendees() throws {
        let json = """
        {"title":"Solo work","start_iso8601":"2026-05-08T09:00","end_iso8601":"2026-05-08T11:00","attendees":[],"notes":""}
        """
        let parsed = try CalendarMode.parseLLMResponse(json)
        #expect(parsed.attendees.isEmpty)
    }
}
