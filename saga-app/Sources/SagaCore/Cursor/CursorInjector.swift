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

    public func type(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        log.debug("Indsætter \(utf16.count) UTF-16 chars")

        // CGEventKeyboardSetUnicodeString tager max 20 chars per event;
        // chunker for sikkerhed
        for chunk in utf16.chunks(of: 16) {
            postUnicode(chunk)
            usleep(charDelayMicroseconds)
        }
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
