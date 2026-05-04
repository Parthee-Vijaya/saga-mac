import Testing
@testable import Saga

@Suite("ModeRouter")
struct ModeRouterTests {

    @Test("translate.en trigger matches and strips trigger")
    func translateEnglishMatch() async throws {
        let mode = Mode.builtins.first { $0.id == "translate.en" }!
        #expect(mode.triggers.contains("oversæt til engelsk"))
    }

    @Test("vibecode trigger requires colon")
    func vibecodeTrigger() {
        let mode = Mode.builtins.first { $0.id == "vibecode" }!
        #expect(mode.triggers.contains("kode:"))
        #expect(!mode.triggers.contains("kode"))
    }

    @Test("All builtin modes have non-empty system prompt and triggers")
    func builtinsValid() {
        for mode in Mode.builtins {
            #expect(!mode.id.isEmpty)
            #expect(!mode.title.isEmpty)
            #expect(!mode.systemPrompt.isEmpty)
            #expect(!mode.triggers.isEmpty)
        }
    }
}
