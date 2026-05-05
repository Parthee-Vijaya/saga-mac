import Testing
@testable import Saga

@Suite("CompanionSession")
@MainActor
struct CompanionSessionTests {

    @Test("New session has no messages")
    func newSessionEmpty() {
        let session = CompanionSession()
        #expect(session.messages.isEmpty)
    }

    @Test("messagesForLLM always includes system prompt as first")
    func systemPromptFirst() {
        let session = CompanionSession(systemPrompt: "TEST")
        let llm = session.messagesForLLM()
        #expect(llm.count == 1)
        #expect(llm[0].role == .system)
        #expect(llm[0].content == "TEST")
    }

    @Test("appendUser adds message and includes screenshot")
    func appendUserWithScreenshot() {
        let session = CompanionSession()
        let dummyPNG = Data([0x89, 0x50, 0x4E, 0x47])  // dummy bytes
        session.appendUser("Hvad ser jeg?", screenshot: dummyPNG)
        #expect(session.messages.count == 1)
        #expect(session.messages[0].role == .user)
        #expect(session.messages[0].screenshotPNG == dummyPNG)
    }

    @Test("Empty user message is ignored")
    func emptyUserIgnored() {
        let session = CompanionSession()
        session.appendUser("   ")
        #expect(session.messages.isEmpty)
    }

    @Test("appendAssistant trims whitespace")
    func appendAssistantTrims() {
        let session = CompanionSession()
        session.appendAssistant("  hello  ")
        #expect(session.messages.first?.content == "hello")
    }

    @Test("Trim drops oldest pairs when over limit")
    func trimOldestPairs() {
        let session = CompanionSession(maxTurnPairs: 2)
        for i in 1...4 {
            session.appendUser("user-\(i)")
            session.appendAssistant("assistant-\(i)")
        }
        // After 4 pairs with max=2, the first 2 pairs should be dropped
        let userContents = session.messages.filter { $0.role == .user }.map { $0.content }
        #expect(userContents == ["user-3", "user-4"])
        #expect(session.messages.count == 4)  // 2 pairs = 4 messages
    }

    @Test("messagesForLLM includes system + all current messages")
    func messagesForLLMIncludesEverything() {
        let session = CompanionSession()
        session.appendUser("Hej")
        session.appendAssistant("Hej tilbage")
        let llm = session.messagesForLLM()
        #expect(llm.count == 3)  // system + user + assistant
        #expect(llm[0].role == .system)
        #expect(llm[1].content == "Hej")
        #expect(llm[2].content == "Hej tilbage")
    }

    @Test("Reset clears messages but preserves system prompt usage")
    func resetClears() {
        let session = CompanionSession(systemPrompt: "PRESERVED")
        session.appendUser("first")
        session.reset()
        let llm = session.messagesForLLM()
        #expect(llm.count == 1)  // only system
        #expect(llm[0].content == "PRESERVED")
    }

    @Test("userJustEndedSession detects 'tak'")
    func endSessionDanish() {
        let session = CompanionSession()
        session.appendUser("Tak")
        #expect(session.userJustEndedSession())
    }

    @Test("userJustEndedSession detects 'goodbye'")
    func endSessionEnglish() {
        let session = CompanionSession()
        session.appendUser("Goodbye")
        #expect(session.userJustEndedSession())
    }

    @Test("userJustEndedSession does not match unrelated text")
    func endSessionFalse() {
        let session = CompanionSession()
        session.appendUser("Hvad ser jeg på skærmen lige nu")
        #expect(!session.userJustEndedSession())
    }

    @Test("CompanionMessage Codable round-trip preserves all fields")
    func messageCodable() throws {
        let original = CompanionMessage(
            role: .user,
            content: "test",
            screenshotPNG: Data([1, 2, 3])
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompanionMessage.self, from: data)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.screenshotPNG == original.screenshotPNG)
    }
}
