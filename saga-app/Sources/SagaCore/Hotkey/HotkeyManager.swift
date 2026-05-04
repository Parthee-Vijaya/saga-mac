import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

/// Lytter efter Fn-tast-hold. Bruger CGEventTap (kræver Accessibility-permission).
///
/// På moderne Macs er Fn = "globe"-tasten (kCGEventFlagMaskSecondaryFn). Single-press er
/// fri (Apple ændrede default-dictation til Fn-Fn double-tap), så hold-to-dictate er sikkert.
@MainActor
public final class HotkeyManager {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "hotkey")

    public var onHoldStart: (() -> Void)?
    public var onHoldEnd: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHolding = false

    public init() {}

    public func startListening() {
        guard ensureAccessibility() else {
            log.warning("Accessibility-permission mangler — hotkey er inaktiv indtil brugeren granter den")
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
        log.info("Hotkey-listener aktiv")
    }

    public func stopListening() {
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

    fileprivate func handleFlagsChanged(fnDown: Bool) {
        if fnDown && !isHolding {
            isHolding = true
            log.debug("Fn down → start recording")
            onHoldStart?()
        } else if !fnDown && isHolding {
            isHolding = false
            log.debug("Fn up → stop recording")
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

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Tap blev disabled (timeout / interrupt). Re-enabling sker fra runLoop-tråden.
        return Unmanaged.passUnretained(event)
    }
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    let fnDown = event.flags.contains(.maskSecondaryFn)
    Task { @MainActor in
        manager.handleFlagsChanged(fnDown: fnDown)
    }
    return Unmanaged.passUnretained(event)
}
