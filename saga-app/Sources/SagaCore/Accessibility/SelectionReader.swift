import AppKit
import ApplicationServices
import Foundation
import OSLog

/// Læser den aktuelt-markerede tekst i den frontmost app via AXUIElement.
///
/// Bruges af voice-edit-mode: når brugeren har markeret tekst i en hvilken som
/// helst app og siger "ret denne sætning til at være mere formel", skal Saga
/// kunne læse den markerede tekst, sende den + instruktionen til LM Studio,
/// og indsætte resultatet (som overskriver den markerede tekst når der typed'es).
///
/// Kræver Accessibility-permission (allerede grantet for hotkey + cursor-injection).
public struct SelectionReader: Sendable {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "selection")

    public init() {}

    /// Returnér den markerede tekst i den fokuserede app, eller nil hvis ingen
    /// selection findes / API'et ikke svarer / appen ikke understøtter AX.
    @MainActor
    public func currentSelection() -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            Self.log.debug("Ingen frontmost app")
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        let err1 = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard err1 == .success, let focusedRaw = focusedRef else {
            Self.log.debug("Ingen focused UI element (\(err1.rawValue))")
            return nil
        }
        // CFTypeRef → AXUIElement bridge
        let focused = focusedRaw as! AXUIElement // swiftlint:disable:this force_cast

        var selectionRef: CFTypeRef?
        let err2 = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectionRef
        )
        guard err2 == .success else {
            Self.log.debug("Element understøtter ikke kAXSelectedText (\(err2.rawValue))")
            return nil
        }

        guard let text = selectionRef as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
}
