@preconcurrency import AppKit
import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

/// Skærm-capture til vision-modes. Bruger ScreenCaptureKit (macOS 12.3+, krævet
/// fra macOS 14+ da legacy CGWindowListCreateImage er deprecated).
@MainActor
public final class ScreenVision {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "vision")

    public init() {}

    public var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Capture nuværende foran-vindue. Returnerer PNG-data der kan base64'es
    /// til vision-LLM-call. Returnerer nil hvis screen-recording-permission mangler
    /// eller capture fejler.
    public func captureFrontmostWindow(maxWidth: CGFloat = 1280) async -> Data? {
        guard hasPermission else {
            log.warning("Screen capture permission mangler — fall back til full-display")
            return await captureFullScreen(maxWidth: maxWidth)
        }

        do {
            let content = try await SCShareableContent.current
            // Find første tilgængelige display
            guard let display = content.displays.first else {
                log.warning("Ingen displays tilgængelige")
                return nil
            }

            // Find foran-vindue (eksklusiv Saga selv)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let frontWindow = content.windows
                .filter { $0.owningApplication?.processID != ownPID }
                .filter { $0.frame.width > 200 && $0.frame.height > 200 }
                .filter { $0.isOnScreen }
                .sorted { $0.windowLayer < $1.windowLayer }
                .first

            let filter: SCContentFilter
            if let frontWindow {
                filter = SCContentFilter(desktopIndependentWindow: frontWindow)
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }

            let config = SCStreamConfiguration()
            config.width = Int(min(maxWidth, CGFloat(filter.contentRect.width)))
            config.height = Int(CGFloat(config.width) * filter.contentRect.height / filter.contentRect.width)
            config.scalesToFit = true
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return pngData(from: cgImage)
        } catch {
            log.error("Screen capture fejlede: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func captureFullScreen(maxWidth: CGFloat = 1280) async -> Data? {
        guard hasPermission else { return nil }
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(min(maxWidth, CGFloat(display.width)))
            config.height = Int(CGFloat(config.width) * CGFloat(display.height) / CGFloat(display.width))
            config.scalesToFit = true
            config.showsCursor = false
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return pngData(from: cgImage)
        } catch {
            log.error("Full screen capture fejlede: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func pngData(from cgImage: CGImage) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    public func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
