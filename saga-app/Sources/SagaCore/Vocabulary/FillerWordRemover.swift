import Foundation

/// Strip danske pauseord/filler-fraser fra Canary's transcript.
///
/// Køres efter VocabularyPostProcessor (custom rettelser først, så filler-
/// stripping på den korrigerede tekst). Inspireret af Wispr Flow's "AI-layer"
/// der automatisk fjerner "um", "uh", "like" — her tilpasset dansk.
///
/// **Strategi:** to kategorier af filler-fraser:
///
/// 1. **Sikre** — entydigt pauseord, ingen normal betydning. Strippes altid.
///    `øh, øhm, øhh, ehm, ehh, eh, like` (sidste = engelsk pause-fyld der ofte
///    sniger sig ind).
///
/// 2. **Kontekst-sensitive** — har normal betydning men bruges også som filler.
///    Strippes KUN når de står som standalone interjektion. Implementeres ved
///    kun at matche når de er omsluttet af komma/whitespace/begin-of-string,
///    og de IKKE indgår i en kendt frase.
///
/// Designet uden afhængighed af UserDefaults eller ObservableObject for at være
/// nem at unit-teste isoleret. SagaController owns toggle-state via @Published.
public struct FillerWordRemover: Sendable {
    /// "Sikre" filler-ord — strippes altid når de findes som hele ord.
    public static let safeFillers: [String] = [
        "øh", "øhm", "øhh", "ehm", "ehh", "eh",
    ]

    /// "Kontekst-sensitive" filler-fraser — strippes når de står som
    /// standalone interjektion (omsluttet af komma/whitespace).
    public static let contextualFillers: [String] = [
        "altså",
        "ligesom",
        "sådan set",
        "hvad hedder det",
    ]

    /// Brugerens egne extra fillers (typisk fra UserDefaults).
    public let extraFillers: [String]

    public init(extraFillers: [String] = []) {
        self.extraFillers = extraFillers
    }

    /// Anvend filler-stripping på `text`. Returnerer renset string med
    /// whitespace + punktuation pænt collapsed.
    public func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // 1. Strip sikre fillers — match som hele ord, case-insensitive
        let allSafe = Self.safeFillers + extraFillers
        for filler in allSafe {
            result = stripWholeWord(filler, from: result)
        }

        // 2. Strip kontekst-sensitive fillers — kun når de står som
        //    standalone interjektion (omgivet af komma/whitespace/punktuation)
        for filler in Self.contextualFillers {
            result = stripStandaloneInterjection(filler, from: result)
        }

        // 3. Cleanup: collapse double-spaces, fjern tomme komma-sekvenser,
        //    trim begin/end
        result = cleanupWhitespaceAndPunctuation(result)

        return result
    }

    /// Strip filler som hele ord (word boundaries). Erstat med space så vi
    /// ikke smelter omgivende ord sammen.
    private func stripWholeWord(_ filler: String, from text: String) -> String {
        // Escape regex-special chars i filler (selvom danske bogstaver er fine)
        let escaped = NSRegularExpression.escapedPattern(for: filler)
        // \b virker ikke perfekt for danske bogstaver i ICU-regex — brug
        // explicit lookahead/lookbehind med whitespace/punktuation/start/end
        let pattern = "(?i)(?<=^|[\\s,.;:!?\\-])\(escaped)(?=$|[\\s,.;:!?\\-])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    /// Strip filler kun når den står som standalone interjektion — typisk
    /// efterfulgt eller foran-gået af komma. "Altså, jeg vil..." → "jeg vil..."
    /// men "der er altså ikke noget" bevarer "altså".
    private func stripStandaloneInterjection(_ filler: String, from text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: filler)
        // Match i 3 mønstre:
        //  a) Begin-of-string + filler + komma:    "Altså, jeg vil..."
        //  b) Komma + filler + komma:              "..., altså, ..."
        //  c) Filler alene + komma + slut:         (fjern komma-trailers)
        let patterns = [
            "(?i)^\(escaped)\\s*,\\s*",                  // a
            "(?i),\\s*\(escaped)\\s*,",                  // b
            "(?i)\\s+\(escaped)\\s*,\\s*",               // c
        ]
        var result = text
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            // Erstat med space (eller komma-space ved b-mønsteret) — cleanup
            // håndterer overskydende whitespace bagefter
            let replacement = pattern.contains(",\\s*\(escaped)\\s*,") ? ", " : " "
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    /// Cleanup efter strip: collapse double-spaces, fjern tomme komma-
    /// sekvenser ("og , så" → "og så"), trim ends, capitalize første bogstav.
    private func cleanupWhitespaceAndPunctuation(_ text: String) -> String {
        var result = text

        // Collapse multiple whitespaces til én
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }

        // Fjern space før komma/punktum: "ord ," → "ord,"
        if let regex = try? NSRegularExpression(pattern: "\\s+([,.;:!?])") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }

        // Fjern duplikerede kommaer: "ord,, mere" eller "ord, , mere" → "ord, mere"
        if let regex = try? NSRegularExpression(pattern: ",\\s*,+") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: ",")
        }

        // Fjern leading komma efter strip: ", jeg vil..." → "jeg vil..."
        if let regex = try? NSRegularExpression(pattern: "^[,\\s]+") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Trim ends
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize første bogstav hvis det er nedsat efter strip
        // (kun hvis første tegn er lowercase letter)
        if let firstChar = result.first, firstChar.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        return result
    }
}
