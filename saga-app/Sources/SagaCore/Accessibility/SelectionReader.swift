import AppKit
import ApplicationServices
import CoreGraphics
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
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Self.log.info("Ingen frontmost app")
            return nil
        }
        let pid = frontApp.processIdentifier
        let bundleId = frontApp.bundleIdentifier ?? "unknown"
        Self.log.info("SelectionReader: frontmost=\(bundleId, privacy: .public) pid=\(pid, privacy: .public)")

        let appElement = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        let err1 = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard err1 == .success, let focusedRaw = focusedRef else {
            Self.log.info("AX-fejl: ingen focused UI element (err=\(err1.rawValue, privacy: .public)) i \(bundleId, privacy: .public)")
            return nil
        }
        let focused = focusedRaw as! AXUIElement // swiftlint:disable:this force_cast

        // Log hvilken role focused element har — afslører om det er TextField,
        // TextArea, WebArea (Safari/Chrome krævende ekstra perm) osv.
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            Self.log.info("Focused role: \(role, privacy: .public)")
        }

        var selectionRef: CFTypeRef?
        let err2 = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectionRef
        )
        guard err2 == .success else {
            Self.log.info("AX-fejl: kAXSelectedText ikke supportet (err=\(err2.rawValue, privacy: .public))")
            return nil
        }

        guard let text = selectionRef as? String else {
            Self.log.info("Selection-ref er ikke en String")
            return nil
        }
        guard !text.isEmpty else {
            Self.log.info("Selection er tom")
            return nil
        }
        Self.log.info("Selection læst: \(text.count, privacy: .public) chars")
        return text
    }

    /// Fallback: simulerer Cmd+C, læser pasteboard, gendanner det oprindelige
    /// clipboard-indhold. Virker i Electron-apps (Claude, Slack, VSCode, Notion)
    /// og webviews der ikke eksponerer kAXSelectedText.
    ///
    /// Trade-off: hvis brugeren havde et billede eller fil i clipboard, gendannes
    /// kun string-indholdet (string er 99% af clipboard-brug). Tager ~80ms.
    @MainActor
    public func currentSelectionViaClipboard() -> String? {
        let pb = NSPasteboard.general
        let oldString = pb.string(forType: .string)
        let beforeCount = pb.changeCount

        Self.log.info("Clipboard-fallback: simulerer Cmd+C")
        sendCommandC()

        // Vent på at appen håndterer Cmd+C og opdaterer pasteboard.
        // 80ms er kompromis mellem latency og pålidelighed på langsomme apps.
        usleep(80_000)

        guard pb.changeCount > beforeCount else {
            Self.log.info("Clipboard-fallback: pasteboard uændret efter Cmd+C — ingen markering")
            // Gendan ikke noget — pb er præcis som den var
            return nil
        }

        let selection = pb.string(forType: .string)

        // Gendan oprindeligt indhold (string-only — billeder/filer mistes)
        pb.clearContents()
        if let oldString {
            pb.setString(oldString, forType: .string)
        }

        guard let selection, !selection.isEmpty else {
            Self.log.info("Clipboard-fallback: pasteboard ændret men ingen string")
            return nil
        }
        Self.log.info("Clipboard-fallback: læste \(selection.count, privacy: .public) chars")
        return selection
    }

    @MainActor
    private func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 0x08  // 'c'

        let down = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
