import Testing
@testable import Saga

@Suite("SentenceFlusher")
struct SentenceFlusherTests {

    @Test("Empty input yields nothing")
    func emptyInput() {
        var flusher = SentenceFlusher()
        #expect(flusher.append("").isEmpty)
        #expect(flusher.flush() == nil)
    }

    @Test("Complete sentence with period+space emits")
    func completeSentence() {
        var flusher = SentenceFlusher(minLength: 5)
        let result = flusher.append("Hej verden. ")
        #expect(result == ["Hej verden."])
    }

    @Test("Sentence without trailing space waits for more input")
    func sentenceWithoutTrailingSpaceWaits() {
        var flusher = SentenceFlusher(minLength: 5)
        let result = flusher.append("Hej verden.")
        // Ingen flush — vi mangler whitespace efter "."
        #expect(result.isEmpty)
        // Når vi tilføjer space efter, kommer den
        let result2 = flusher.append(" ")
        #expect(result2 == ["Hej verden."])
    }

    @Test("Multiple sentences in one chunk")
    func multipleSentences() {
        var flusher = SentenceFlusher(minLength: 5)
        let result = flusher.append("Første sætning. Anden sætning. ")
        #expect(result == ["Første sætning.", "Anden sætning."])
    }

    @Test("Streaming chunks accumulate correctly")
    func streamingChunks() {
        var flusher = SentenceFlusher(minLength: 5)
        var output: [String] = []
        output.append(contentsOf: flusher.append("Hej "))
        output.append(contentsOf: flusher.append("verden"))
        output.append(contentsOf: flusher.append(". Hvordan "))
        output.append(contentsOf: flusher.append("går det? "))
        #expect(output == ["Hej verden.", "Hvordan går det?"])
    }

    @Test("Question mark and exclamation mark are sentence endings")
    func differentEndings() {
        var flusher = SentenceFlusher(minLength: 3)
        let r1 = flusher.append("Hej? ")
        let r2 = flusher.append("Wow! ")
        #expect(r1 == ["Hej?"])
        #expect(r2 == ["Wow!"])
    }

    @Test("Newline is a sentence ending without requiring trailing space")
    func newlineAsEnding() {
        var flusher = SentenceFlusher(minLength: 5)
        let r = flusher.append("Første linje\n")
        #expect(r == ["Første linje"])
    }

    @Test("Short sentences below minLength are buffered with next")
    func shortSentencesBuffered() {
        var flusher = SentenceFlusher(minLength: 20)
        let r1 = flusher.append("Ja. ")
        let r2 = flusher.append("Det er en længere sætning. ")
        #expect(r1.isEmpty)
        // Begge to bliver flushet sammen som én combined sentence
        #expect(r2.count == 1)
        #expect(r2[0].contains("længere"))
    }

    @Test("Flush returns trailing fragment without sentence-ender")
    func flushTrailingFragment() {
        var flusher = SentenceFlusher(minLength: 5)
        _ = flusher.append("Komplet sætning. Halvt fragment uden")
        let tail = flusher.flush()
        #expect(tail == "Halvt fragment uden")
    }

    @Test("Flush returns nil when buffer is empty")
    func flushEmpty() {
        var flusher = SentenceFlusher()
        _ = flusher.append("Hej verden. ")
        #expect(flusher.flush() == nil)
    }

    @Test("Reset clears buffer")
    func resetClears() {
        var flusher = SentenceFlusher()
        _ = flusher.append("Halvt fragment")
        flusher.reset()
        #expect(flusher.flush() == nil)
    }

    @Test("Decimal numbers don't trigger false splits")
    func decimalsDontSplit() {
        var flusher = SentenceFlusher(minLength: 5)
        // "1.5" har "." men intet space efter — burde IKKE flushe
        let r = flusher.append("Tallet er 1.5 og det er rigtigt. ")
        #expect(r.count == 1)
        #expect(r[0].contains("1.5"))
    }
}
