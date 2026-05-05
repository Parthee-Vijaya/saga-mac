import Foundation
import Testing
@testable import Saga

@Suite("KeychainStore")
struct KeychainStoreTests {
    /// Vi bruger en unik test-key per kørsel for at undgå konflikt med en
    /// rigtig gemt API-key. Cleanup sker via deinit i hver test.
    private let testKey = "saga.tests.keychain.\(UUID().uuidString)"

    @Test("Read returns nil when key not present")
    func readMissingKey() {
        let key = "saga.tests.missing.\(UUID().uuidString)"
        #expect(KeychainStore.read(key) == nil)
        #expect(!KeychainStore.exists(key))
    }

    @Test("Write then read round-trip preserves value")
    func roundTrip() {
        let value = "test-secret-value-\(UUID().uuidString)"
        #expect(KeychainStore.write(value, for: testKey))
        defer { _ = KeychainStore.delete(testKey) }
        #expect(KeychainStore.read(testKey) == value)
        #expect(KeychainStore.exists(testKey))
    }

    @Test("Write overwrites existing value")
    func writeOverwrites() {
        _ = KeychainStore.write("first", for: testKey)
        defer { _ = KeychainStore.delete(testKey) }
        #expect(KeychainStore.read(testKey) == "first")
        _ = KeychainStore.write("second", for: testKey)
        #expect(KeychainStore.read(testKey) == "second")
    }

    @Test("Empty string write deletes the key")
    func emptyStringDeletes() {
        _ = KeychainStore.write("something", for: testKey)
        defer { _ = KeychainStore.delete(testKey) }
        #expect(KeychainStore.exists(testKey))
        _ = KeychainStore.write("", for: testKey)
        #expect(!KeychainStore.exists(testKey))
    }

    @Test("Delete is idempotent — returns true even when key absent")
    func deleteIdempotent() {
        let key = "saga.tests.idempotent.\(UUID().uuidString)"
        #expect(KeychainStore.delete(key))
        #expect(KeychainStore.delete(key))
    }

    @Test("Unicode values survive round-trip")
    func unicodeRoundTrip() {
        let value = "🔑 Æøå · 漢字 · سلام"
        _ = KeychainStore.write(value, for: testKey)
        defer { _ = KeychainStore.delete(testKey) }
        #expect(KeychainStore.read(testKey) == value)
    }
}
