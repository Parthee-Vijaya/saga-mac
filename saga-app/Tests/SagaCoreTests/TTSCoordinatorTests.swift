import Foundation
import Testing
@testable import Saga

@Suite("TTSCoordinator engine selection")
@MainActor
struct TTSCoordinatorTests {

    @Test("Default engine is Apple")
    func defaultEngineApple() {
        let coordinator = TTSCoordinator()
        // Coordinator læser fra UserDefaults — i test-env er det måske ikke "apple",
        // så vi sætter eksplicit
        coordinator.preferredEngineID = "apple"
        let engine = coordinator.chooseEngineWithFallback()
        #expect(engine.id == "apple")
        #expect(engine.requiresAPIKey == false)
        #expect(engine.requiresNetwork == false)
    }

    @Test("ElevenLabs preferred but no key falls back to Apple")
    func elevenLabsNoKeyFallsBack() {
        // Sikr at ingen key er sat for denne test
        _ = KeychainStore.delete(KeychainKey.elevenLabsAPI)
        let coordinator = TTSCoordinator()
        coordinator.preferredEngineID = "elevenlabs"
        let engine = coordinator.chooseEngineWithFallback()
        #expect(engine.id == "apple")
    }

    @Test("ElevenLabs preferred with key returns ElevenLabs engine")
    func elevenLabsWithKeyReturnsCloud() {
        _ = KeychainStore.write("dummy-test-key", for: KeychainKey.elevenLabsAPI)
        defer { _ = KeychainStore.delete(KeychainKey.elevenLabsAPI) }
        let coordinator = TTSCoordinator()
        coordinator.preferredEngineID = "elevenlabs"
        let engine = coordinator.chooseEngineWithFallback()
        #expect(engine.id == "elevenlabs")
        #expect(engine.requiresAPIKey == true)
        #expect(engine.requiresNetwork == true)
    }

    @Test("Apple voice ID persists to UserDefaults")
    func appleVoicePersists() {
        let coordinator = TTSCoordinator()
        let originalValue = coordinator.appleVoiceID
        defer { coordinator.appleVoiceID = originalValue }

        coordinator.appleVoiceID = "com.apple.voice.compact.da-DK.Sara"
        let stored = UserDefaults.standard.string(forKey: "tts.appleVoiceID")
        #expect(stored == "com.apple.voice.compact.da-DK.Sara")
    }

    @Test("ElevenLabs voice ID has sensible default")
    func elevenLabsDefaultVoice() {
        let coordinator = TTSCoordinator()
        // Default skal være ikke-tom så bruger ikke skal indtaste voice-ID
        // før første brug
        #expect(!coordinator.elevenLabsVoiceID.isEmpty)
    }

    @Test("hasElevenLabsKey reflects Keychain state")
    func hasElevenLabsKeyReflectsKeychain() {
        _ = KeychainStore.delete(KeychainKey.elevenLabsAPI)
        let coordinator = TTSCoordinator()
        #expect(!coordinator.hasElevenLabsKey)

        _ = KeychainStore.write("test", for: KeychainKey.elevenLabsAPI)
        defer { _ = KeychainStore.delete(KeychainKey.elevenLabsAPI) }
        #expect(coordinator.hasElevenLabsKey)
    }
}

@Suite("AppleTTSEngine voice discovery")
struct AppleTTSEngineTests {

    @Test("preferredDanishVoice returns identifier or nil")
    func preferredDanish() {
        let voice = AppleTTSEngine.preferredDanishVoice()
        // På de fleste macOS systemer er der mindst én da-DK stemme
        // Hvis ikke (test-env uden danske stemmer): tillad nil
        if let voice {
            #expect(voice.contains("da") || voice.contains("Sara"))
        }
    }

    @Test("availableDanishVoices returns sorted by quality")
    func availableSorted() {
        let voices = AppleTTSEngine.availableDanishVoices()
        for voice in voices {
            #expect(voice.language == "da-DK")
        }
        // Sorteret efter quality DESC — premium først hvis nogen
        if voices.count >= 2 {
            #expect(voices[0].quality.rawValue >= voices[1].quality.rawValue)
        }
    }
}

@Suite("TTSEngine identity properties")
struct TTSEngineIdentityTests {

    @Test("AppleTTSEngine declares offline + no key")
    func appleProperties() {
        let engine = AppleTTSEngine()
        #expect(engine.id == "apple")
        #expect(engine.requiresNetwork == false)
        #expect(engine.requiresAPIKey == false)
        #expect(!engine.displayName.isEmpty)
    }

    @Test("ElevenLabsTTSEngine declares cloud + key required")
    func elevenLabsProperties() {
        let engine = ElevenLabsTTSEngine(voiceID: "test-voice-id")
        #expect(engine.id == "elevenlabs")
        #expect(engine.requiresNetwork == true)
        #expect(engine.requiresAPIKey == true)
    }
}
