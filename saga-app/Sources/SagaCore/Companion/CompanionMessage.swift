import Foundation

/// Én tur i en Companion-samtale. Mappes 1:1 til OpenAI's chat-message-format
/// så `LMStudioBridge.chatStream` kan sende det direkte uden konvertering.
public struct CompanionMessage: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let content: String

    /// Optional PNG-data for screenshot ved denne tur (kun user-messages, M5/Vision).
    /// Sendes som base64 multimodal-content hvis ikke nil. Gemmes også til debugging.
    public let screenshotPNG: Data?

    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        screenshotPNG: Data? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.screenshotPNG = screenshotPNG
        self.timestamp = timestamp
    }
}
