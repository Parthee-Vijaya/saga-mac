import Foundation
import Testing
@testable import Saga

// MARK: - Mocks

/// Mock-bridge der kan konfigureres til succes eller fejl. Tæller kald så
/// tests kan verificere hvilken engine routeren faktisk ramte.
private final class MockDanishBridge: DanishASRBridging, @unchecked Sendable {
    var isReady: Bool
    var resultText: String
    var shouldThrow: Bool
    private(set) var callCount = 0

    init(isReady: Bool = true, resultText: String = "mock", shouldThrow: Bool = false) {
        self.isReady = isReady
        self.resultText = resultText
        self.shouldThrow = shouldThrow
    }

    func transcribe(pcm: CapturedAudio, language: String) async throws -> TranscribeResult {
        callCount += 1
        if shouldThrow {
            throw ASRBridgeError.notReady
        }
        return TranscribeResult(text: resultText, durationMs: 1000, inferenceMs: 100, rtf: 0.1)
    }
}

private final class MockAppleBridge: AppleSpeechBridging, @unchecked Sendable {
    var resultText: String
    private(set) var callCount = 0

    init(resultText: String = "apple") {
        self.resultText = resultText
    }

    func transcribe(pcm: CapturedAudio, languageCode: String) async throws -> TranscribeResult {
        callCount += 1
        return TranscribeResult(text: resultText, durationMs: 1000, inferenceMs: 100, rtf: 0.1)
    }
}

private func makeAudio() -> CapturedAudio {
    CapturedAudio(samples: Array(repeating: 0.0, count: 16000), sampleRate: 16000)
}

// MARK: - Routing-tests

@Suite("MultilingualASRRouter")
struct MultilingualASRRouterTests {

    @Test("Dansk + Hviske valgt + Hviske klar → Hviske bruges, label = Hviske")
    func danishHviskeReady() async throws {
        let canary = MockDanishBridge(resultText: "canary")
        let hviske = MockDanishBridge(resultText: "hviske")
        let apple = MockAppleBridge()
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        let result = try await router.transcribe(pcm: makeAudio(), language: .danish, preferredDanishEngine: .hviske)

        #expect(result.text == "hviske")
        #expect(result.engineLabel == "Hviske")
        #expect(hviske.callCount == 1)
        #expect(canary.callCount == 0)
    }

    @Test("Dansk + Hviske valgt men IKKE klar → Canary bruges, label = Canary")
    func danishHviskeNotReady() async throws {
        let canary = MockDanishBridge(resultText: "canary")
        let hviske = MockDanishBridge(isReady: false, resultText: "hviske")
        let apple = MockAppleBridge()
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        let result = try await router.transcribe(pcm: makeAudio(), language: .danish, preferredDanishEngine: .hviske)

        #expect(result.text == "canary")
        #expect(result.engineLabel == "Canary")
        #expect(hviske.callCount == 0)
        #expect(canary.callCount == 1)
    }

    @Test("Dansk + Canary som preferred → Canary bruges direkte")
    func danishCanaryDefault() async throws {
        let canary = MockDanishBridge(resultText: "canary")
        let hviske = MockDanishBridge(resultText: "hviske")
        let apple = MockAppleBridge()
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        let result = try await router.transcribe(pcm: makeAudio(), language: .danish, preferredDanishEngine: .canary)

        #expect(result.text == "canary")
        #expect(result.engineLabel == "Canary")
        #expect(hviske.callCount == 0)
    }

    @Test("Hviske fejler runtime → fallback til Canary, label = Canary")
    func hviskeFailsFallbackToCanary() async throws {
        let canary = MockDanishBridge(resultText: "canary")
        let hviske = MockDanishBridge(resultText: "hviske", shouldThrow: true)
        let apple = MockAppleBridge()
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        let result = try await router.transcribe(pcm: makeAudio(), language: .danish, preferredDanishEngine: .hviske)

        #expect(result.text == "canary")
        #expect(result.engineLabel == "Canary")
        #expect(hviske.callCount == 1)
        #expect(canary.callCount == 1)
    }

    @Test("Begge dansk-engines fejler → ASRRouterError.bothDanishEnginesFailed")
    func bothEnginesFail() async {
        let canary = MockDanishBridge(shouldThrow: true)
        let hviske = MockDanishBridge(shouldThrow: true)
        let apple = MockAppleBridge()
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        await #expect(throws: ASRRouterError.self) {
            try await router.transcribe(pcm: makeAudio(), language: .danish, preferredDanishEngine: .hviske)
        }
        #expect(apple.callCount == 0)
    }

    @Test("Tamilsk → Apple Speech (Canary supporterer ikke), label = Apple Speech")
    func tamilGoesToApple() async throws {
        let canary = MockDanishBridge(resultText: "canary")
        let hviske = MockDanishBridge(resultText: "hviske")
        let apple = MockAppleBridge(resultText: "apple")
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        let result = try await router.transcribe(pcm: makeAudio(), language: .tamil, preferredDanishEngine: .canary)

        #expect(result.text == "apple")
        #expect(result.engineLabel == "Apple Speech")
        #expect(canary.callCount == 0)
        #expect(apple.callCount == 1)
    }

    @Test("Engelsk + Hviske som preferred → Canary (Hviske er dansk-only)")
    func englishIgnoresHviskePreference() async throws {
        let canary = MockDanishBridge(resultText: "canary")
        let hviske = MockDanishBridge(resultText: "hviske")
        let apple = MockAppleBridge()
        let router = MultilingualASRRouter(canary: canary, hviske: hviske, apple: apple)

        let result = try await router.transcribe(pcm: makeAudio(), language: .english, preferredDanishEngine: .hviske)

        #expect(result.text == "canary")
        #expect(result.engineLabel == "Canary")
        #expect(hviske.callCount == 0)
    }
}

// MARK: - DanishEngine

@Suite("DanishEngine")
struct DanishEngineTests {

    @Test("Alle cases har displayName og description")
    func allCasesHaveLabels() {
        for engine in DanishEngine.allCases {
            #expect(!engine.displayName.isEmpty)
            #expect(!engine.description.isEmpty)
        }
    }

    @Test("Raw-values er stabile (persisteres i UserDefaults)")
    func rawValuesStable() {
        #expect(DanishEngine.canary.rawValue == "canary")
        #expect(DanishEngine.hviske.rawValue == "hviske")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for engine in DanishEngine.allCases {
            let data = try JSONEncoder().encode(engine)
            let decoded = try JSONDecoder().decode(DanishEngine.self, from: data)
            #expect(decoded == engine)
        }
    }
}

// MARK: - TranscribeResult engineLabel

@Suite("TranscribeResult")
struct TranscribeResultTests {

    @Test("withEngineLabel bevarer alle felter og sætter label")
    func withEngineLabelPreservesFields() {
        let original = TranscribeResult(text: "hej", durationMs: 2000, inferenceMs: 250, rtf: 0.125)
        #expect(original.engineLabel == nil)

        let stamped = original.withEngineLabel("Hviske")
        #expect(stamped.text == "hej")
        #expect(stamped.durationMs == 2000)
        #expect(stamped.inferenceMs == 250)
        #expect(stamped.rtf == 0.125)
        #expect(stamped.engineLabel == "Hviske")
    }
}
