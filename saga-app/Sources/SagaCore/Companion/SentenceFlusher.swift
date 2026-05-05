import Foundation

/// Buffer der ophober streaming-tokens og emitter komplette sætninger til TTS
/// så lyd-playback kan starte ved første sætning i stedet for at vente på fuldt LLM-svar.
///
/// Pure-logic struct — ingen UI-afhængighed. Designet til at være stateful
/// over én generering. Reset mellem turns.
public struct SentenceFlusher {
    private var buffer: String = ""

    /// Tegn der markerer slutningen af en sætning. "?", "!" og "." gælder kun
    /// hvis efterfulgt af whitespace eller end-of-buffer (undgår 1.5 → halv-flush).
    private static let sentenceEnders: [Character] = [".", "?", "!", "\n"]

    /// Min sætningslængde der må flushes. Forhindrer micro-fragmenter
    /// ("Ja.") fra at blive sendt til TTS som separate calls — det er bedre
    /// at samle dem med næste sætning.
    public let minLength: Int

    public init(minLength: Int = 12) {
        self.minLength = minLength
    }

    /// Append nye tokens og returnér færdige sætninger der er klar til TTS.
    /// Resterende ufærdig tekst forbliver i buffer.
    public mutating func append(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        return drainCompleteSentences()
    }

    /// Tøm buffer fuldstændig — bruges når LLM-strømmen er færdig
    /// og vi vil have det sidste fragment talt selv hvis det ikke ender på "."
    public mutating func flush() -> String? {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remaining.isEmpty ? nil : remaining
    }

    /// Reset til fresh state.
    public mutating func reset() {
        buffer = ""
    }

    /// Træk komplette sætninger ud af buffer; behold ufærdig rest.
    private mutating func drainCompleteSentences() -> [String] {
        var results: [String] = []
        var current = ""
        var sentenceStart = buffer.startIndex
        var i = buffer.startIndex

        while i < buffer.endIndex {
            current.append(buffer[i])

            if Self.sentenceEnders.contains(buffer[i]) {
                let next = buffer.index(after: i)
                let isLastChar = next == buffer.endIndex
                let nextIsWhitespace = !isLastChar && buffer[next].isWhitespace

                if nextIsWhitespace || buffer[i] == "\n" {
                    let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if sentence.count >= minLength {
                        results.append(sentence)
                        sentenceStart = next
                        current = ""
                    }
                }
                // Hvis det er sidste tegn (ingen whitespace efter): vent på mere
            }
            i = buffer.index(after: i)
        }

        // Behold ufærdig rest i buffer
        buffer = String(buffer[sentenceStart...])
        return results
    }
}
