import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Inserter tekst ved markøren via CGEvent unicode-keyboard events.
/// Kræver Accessibility-permission (samme som HotkeyManager).
@MainActor
public final class CursorInjector {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "cursor")

    /// Pacing — for hurtigt og target-app kan miste characters
    public var charDelayMicroseconds: UInt32 = 1_500

    public init() {}

    /// Kendte Electron-apps der opslugir CGEvent unicode-injection. For dem
    /// bruger vi paste-flow fra start (sparer ~80ms latency vs prøv-først-
    /// fall-back-strategien).
    private static let electronAppBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop",  // Claude
        "com.tinyspeck.slackmacgap",       // Slack
        "com.microsoft.VSCode",            // VS Code
        "com.figma.Desktop",               // Figma
        "com.todoist.mac.Todoist",         // Todoist
        "com.electron.notion",             // Notion
        "notion.id",                       // Notion (alt. ID)
        "com.discord.discord",             // Discord
        "com.spotify.client",              // Spotify
        "md.obsidian",                     // Obsidian
        "com.linear",                      // Linear
        "com.hnc.Discord",                 // Discord (alt. ID)
        "com.github.GitHubClient",         // GitHub Desktop
        "com.postmanlabs.mac",             // Postman
        "com.tdesktop.Telegram",           // Telegram (uses Electron-like)
    ]

    /// True hvis frontmost app sandsynligvis er en Electron-app baseret på
    /// bundleId. Bruges af type() til at vælge optimal injection-strategi.
    public static func isLikelyElectronApp(_ bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return electronAppBundleIDs.contains(bundleId)
    }

    public func type(_ text: String) {
        guard !text.isEmpty else { return }

        // Electron-apps opslugir ofte CGEvent unicode-injection — paste fra
        // start frem for at spilde tid på at prøve unicode-keyboard først.
        // Sparer ~80ms latency for de mest almindelige apps.
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if Self.isLikelyElectronApp(frontmost) {
            log.info("Frontmost \(frontmost ?? "?", privacy: .public) er Electron — bruger paste-strategi fra start")
            paste(text)
            return
        }

        let utf16 = Array(text.utf16)
        log.info("Indsætter \(utf16.count, privacy: .public) UTF-16 chars: \"\(text.prefix(80), privacy: .public)\"")

        // CGEventKeyboardSetUnicodeString tager max 20 chars per event;
        // chunker for sikkerhed
        for chunk in utf16.chunks(of: 16) {
            postUnicode(chunk)
            usleep(charDelayMicroseconds)
        }
    }

    /// Indsætter via clipboard + Cmd+V — pålidelig i Electron-apps (Claude,
    /// Slack, VSCode, Notion, Discord) hvor unicode-keyboard-injection kan
    /// blive opslugt af appens egen IME / shortcut-handling.
    ///
    /// Hvis `targetPID` er sat, aktiveres den app FØR paste'en så fokus
    /// kommer tilbage til der hvor brugeren startede recordingen — det
    /// dækker tilfældet hvor brugeren klikker væk mens LLM tænker.
    public func paste(_ text: String, restoringFocusToPID targetPID: pid_t? = nil) {
        guard !text.isEmpty else { return }
        log.info("Paste'er \(text.utf16.count, privacy: .public) UTF-16 chars: \"\(text.prefix(80), privacy: .public)\"")

        let pb = NSPasteboard.general
        let oldString = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Bring oprindelig app forrest hvis vi har dens PID — uden dette
        // går paste'en til den nuværende frontmost-app (måske LM Studio
        // hvis brugeren klikkede væk for at tjekke progress).
        if let targetPID, let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate()
            // Lille pause så aktivering propagerer før Cmd+V sendes
            usleep(60_000)
        }

        sendCommandV()

        // Vent på at appen har konsumeret paste'en før vi gendanner clipboard
        usleep(120_000)
        pb.clearContents()
        if let oldString {
            pb.setString(oldString, forType: .string)
        }
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09  // 'v'

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func postUnicode(_ chars: [unichar]) {
        // Vi sender én "down" event per chunk (Apple's anbefalede pattern for indsæt-tekst)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            log.error("CGEvent kunne ikke oprettes")
            return
        }

        chars.withUnsafeBufferPointer { ptr in
            event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: ptr.baseAddress)
        }
        event.post(tap: .cghidEventTap)
    }
}

private extension Array {
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
