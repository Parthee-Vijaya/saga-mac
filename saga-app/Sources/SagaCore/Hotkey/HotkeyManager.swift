import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

/// Lytter efter en push-to-talk-tast og kalder onHoldStart/onHoldEnd.
/// Bruger CGEventTap (kræver Accessibility-permission).
///
/// Default er **Right Option** (`⌥` højre side af mellemrumstasten) — virker på
/// alle keyboards inkl. Logitech MX Keys/MX Master, hvor Apples globe/Fn ikke fungerer.
/// Apples `Fn` (kCGEventFlagMaskSecondaryFn) understøttes også som alternativ.
/// User kan ændre via UserDefaults `hotkey` ("rightOption" | "leftOption" | "fn"
/// | "rightCommand" | "rightControl").
@MainActor
public final class HotkeyManager {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "hotkey")

    /// Kaldes når hotkey DOWN. Bool = om Shift også blev holdt nede ved start —
    /// bruges til at trigge voice-edit-mode (Shift+⌥) i stedet for normal dictation.
    public var onHoldStart: ((Bool) -> Void)?
    public var onHoldEnd: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHolding = false

    public init() {}

    public var hotkey: Hotkey {
        get { Hotkey(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotkey") }
    }

    private var retryTask: Task<Void, Never>?

    public func startListening() {
        if !ensureAccessibility() {
            log.warning("Accessibility-permission mangler — venter på grant og prøver igen hvert 2. sekund")
            scheduleRetry()
            return
        }
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: userInfo
        ) else {
            log.error("CGEvent.tapCreate fejlede — sandsynligvis manglende AX-permission")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        log.info("Hotkey-listener aktiv (key=\(self.hotkey.rawValue))")
    }

    public func stopListening() {
        retryTask?.cancel()
        retryTask = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isHolding = false
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                if Task.isCancelled { return }
                if AXIsProcessTrusted() {
                    self.log.info("Accessibility nu granted — aktiverer hotkey")
                    self.retryTask = nil
                    self.startListening()
                    return
                }
            }
        }
    }

    fileprivate func handleHotkey(isDown: Bool, shiftHeld: Bool) {
        if isDown && !isHolding {
            isHolding = true
            log.info("hotkey DOWN — start recording (shift=\(shiftHeld ? "yes" : "no", privacy: .public))")
            onHoldStart?(shiftHeld)
        } else if !isDown && isHolding {
            isHolding = false
            log.info("hotkey UP — stop recording")
            onHoldEnd?()
        }
    }

    @discardableResult
    private func ensureAccessibility() -> Bool {
        let trusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary)
        return trusted
    }
}

public enum Hotkey: String, CaseIterable, Sendable {
    case rightOption    // ⌥ højre — anbefalet, virker på alle keyboards
    case leftOption     // ⌥ venstre
    case rightCommand   // ⌘ højre
    case rightControl   // ⌃ højre
    case fn             // Apple's globe / Fn — virker IKKE på Logitech-keyboards

    /// Key code som CGEvent reporterer i flagsChanged-events. nil = ingen specifik
    /// keycode (Fn rapporteres via flag, ikke key code).
    public var keyCode: Int64? {
        switch self {
        case .rightOption: return 61      // kVK_RightOption
        case .leftOption: return 58       // kVK_Option
        case .rightCommand: return 54     // kVK_RightCommand
        case .rightControl: return 62     // kVK_RightControl
        case .fn: return nil
        }
    }

    /// Den modifier-mask der er sat når denne tast holdes nede.
    public var flagMask: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: return "Højre Option (⌥)"
        case .leftOption: return "Venstre Option (⌥)"
        case .rightCommand: return "Højre Command (⌘)"
        case .rightControl: return "Højre Control (⌃)"
        case .fn: return "Fn / globe (kun Apple-keyboards)"
        }
    }

    /// Kompakt symbol til keyboard-pills i HUD'er (uden parentes-suffix).
    public var keySymbol: String {
        switch self {
        case .rightOption, .leftOption: return "⌥"
        case .rightCommand: return "⌘"
        case .rightControl: return "⌃"
        case .fn: return "fn"
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    // Læs eventet OUTSIDE @MainActor (CGEvent er ikke Sendable)
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flagsRaw = flags.rawValue

    Task { @MainActor in
        let key = manager.hotkey
        let maskHeld = flags.contains(key.flagMask)
        let shiftHeld = flags.contains(.maskShift)

        // Diagnostic logging — info-level + public privacy så vi kan se værdier
        let log = Logger(subsystem: "dk.parthee.saga", category: "hotkey")
        let keyName: String
        switch keyCode {
        case 58: keyName = "LeftOption"
        case 61: keyName = "RightOption"
        case 54: keyName = "RightCmd"
        case 55: keyName = "LeftCmd"
        case 59: keyName = "LeftCtrl"
        case 62: keyName = "RightCtrl"
        case 56: keyName = "LeftShift"
        case 60: keyName = "RightShift"
        case 63: keyName = "Fn"
        default: keyName = "kc\(keyCode)"
        }
        log.info("event: \(keyName, privacy: .public) (kc=\(keyCode, privacy: .public)) flags=0x\(String(flagsRaw, radix: 16), privacy: .public) maskHeld=\(maskHeld ? "yes" : "no", privacy: .public) expecting=\(key.keyCode?.description ?? "nil", privacy: .public)")

        if let expectedKey = key.keyCode {
            if keyCode != expectedKey { return }
            manager.handleHotkey(isDown: maskHeld, shiftHeld: shiftHeld)
        } else {
            manager.handleHotkey(isDown: maskHeld, shiftHeld: shiftHeld)
        }
    }
    return Unmanaged.passUnretained(event)
}
