import Testing
import Foundation
@testable import Saga

@Suite("EnergyVAD")
struct EnergyVADTests {

    @Test("Continuous talk never triggers timeout")
    func continuousTalk() {
        var vad = EnergyVAD(config: VADConfig(silenceThreshold: 0.05, silenceDuration: 1.0, minRecordingDuration: 0.5))
        let start = Date()
        for tick in 0..<100 {
            let event = vad.process(level: 0.6, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            #expect(event == .continue)
        }
    }

    @Test("Silence below threshold for full duration triggers timeout")
    func silenceTriggers() {
        var vad = EnergyVAD(config: VADConfig(silenceThreshold: 0.05, silenceDuration: 1.0, minRecordingDuration: 0.5))
        let start = Date()
        var firedAt: Date?
        for tick in 0..<200 {
            let timestamp = start.addingTimeInterval(Double(tick) * 0.033)
            let event = vad.process(level: 0.01, timestamp: timestamp)
            if event == .silenceTimeout {
                firedAt = timestamp
                break
            }
        }
        #expect(firedAt != nil)
        if let firedAt {
            // Should fire ~1.5s in (0.5 min-duration + 1.0 silence-duration)
            let elapsed = firedAt.timeIntervalSince(start)
            #expect(elapsed >= 1.5)
            #expect(elapsed < 1.7)
        }
    }

    @Test("Silence interrupted by talk resets the timer")
    func silenceInterrupted() {
        var vad = EnergyVAD(config: VADConfig(silenceThreshold: 0.05, silenceDuration: 1.0, minRecordingDuration: 0.5))
        let start = Date()
        // 0.6s talk, 0.5s silence, 0.1s talk, 0.5s silence — cumulative silence > 1s
        // but not contiguous, so no trigger.
        for tick in 0..<18 {
            _ = vad.process(level: 0.6, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
        }
        // 0.5s silence (not enough yet)
        for tick in 18..<33 {
            let event = vad.process(level: 0.01, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            #expect(event == .continue)
        }
        // Talk again — resets
        for tick in 33..<36 {
            _ = vad.process(level: 0.6, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
        }
        // Another 0.5s silence — still shouldn't fire (interrupted)
        for tick in 36..<51 {
            let event = vad.process(level: 0.01, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            #expect(event == .continue)
        }
    }

    @Test("Timeout fires only once even if process() called more after")
    func firesOnce() {
        var vad = EnergyVAD(config: VADConfig(silenceThreshold: 0.05, silenceDuration: 0.5, minRecordingDuration: 0.5))
        let start = Date()
        var fireCount = 0
        for tick in 0..<200 {
            let event = vad.process(level: 0.01, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            if event == .silenceTimeout {
                fireCount += 1
            }
        }
        #expect(fireCount == 1)
    }

    @Test("Reset allows VAD to fire again on a new recording")
    func resetReusable() {
        var vad = EnergyVAD(config: VADConfig(silenceThreshold: 0.05, silenceDuration: 0.5, minRecordingDuration: 0.3))
        let start = Date()
        // First recording: trigger silence
        var firstFired = false
        for tick in 0..<100 {
            let event = vad.process(level: 0.01, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            if event == .silenceTimeout { firstFired = true; break }
        }
        #expect(firstFired)

        // Reset for new recording
        vad.reset()

        // Second recording starts fresh
        let newStart = start.addingTimeInterval(10)
        var secondFired = false
        for tick in 0..<100 {
            let event = vad.process(level: 0.01, timestamp: newStart.addingTimeInterval(Double(tick) * 0.033))
            if event == .silenceTimeout { secondFired = true; break }
        }
        #expect(secondFired)
    }

    @Test("Min-duration prevents premature firing")
    func minDurationGate() {
        var vad = EnergyVAD(config: VADConfig(silenceThreshold: 0.05, silenceDuration: 0.1, minRecordingDuration: 1.0))
        let start = Date()
        // First 1s: even with silence, must not fire (min-duration not yet reached)
        for tick in 0..<30 {
            let event = vad.process(level: 0.01, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            #expect(event == .continue)
        }
        // After 1s: silence-duration of 0.1s should be enough
        var fired = false
        for tick in 30..<60 {
            let event = vad.process(level: 0.01, timestamp: start.addingTimeInterval(Double(tick) * 0.033))
            if event == .silenceTimeout { fired = true; break }
        }
        #expect(fired)
    }
}

@Suite("VADConfig")
struct VADConfigTests {

    @Test("Default config has reasonable values")
    func defaults() {
        let config = VADConfig.default
        #expect(config.silenceThreshold > 0)
        #expect(config.silenceThreshold < 0.5)
        #expect(config.silenceDuration >= 0.5)
        #expect(config.silenceDuration <= 3.0)
    }

    @Test("Codable round-trip preserves config")
    func codableRoundTrip() throws {
        let original = VADConfig(silenceThreshold: 0.1, silenceDuration: 2.0, minRecordingDuration: 0.8)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VADConfig.self, from: data)
        #expect(decoded == original)
    }
}
