import AppKit
import Foundation
import OSLog

/// Daily voice-journal: appendes alle dictations til en markdown-fil per dag.
///
/// Filsti: `~/Saga-journal/YYYY-MM-DD.md` (kan ændres via Settings).
/// Hver entry har timestamp-header og fuld tekst:
///
/// ```markdown
/// # 2026-05-07
///
/// ## 14:23
/// Hej, jeg vil gerne sige tak for mødet i dag.
///
/// ## 14:31
/// Køb mælk, brød og smør på vej hjem.
/// ```
///
/// Brugbar til reflective journaling, møde-noter samlet ét sted, og
/// søg-og-find. Kun aktivt hvis bruger har enabled det i Settings.
@MainActor
public final class JournalStore: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "journal")

    /// Brugerens journal-mappe. Default: ~/Saga-journal/. Kan overskrives
    /// via UserDefaults (path-picker i Settings).
    @Published public var directory: URL {
        didSet {
            UserDefaults.standard.set(directory.path, forKey: "journalDirectory")
        }
    }

    public init() {
        if let savedPath = UserDefaults.standard.string(forKey: "journalDirectory"),
           !savedPath.isEmpty {
            self.directory = URL(fileURLWithPath: savedPath)
        } else {
            // Default: ~/Saga-journal/
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.directory = home.appendingPathComponent("Saga-journal", isDirectory: true)
        }
    }

    /// Append en ny entry til dagens journal-fil. Opretter fil + header
    /// hvis den ikke eksisterer endnu. Tom tekst skipped.
    public func append(text: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Sikr at journal-mappen eksisterer
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.warning("Kunne ikke oprette journal-mappe: \(error.localizedDescription, privacy: .public)")
            return
        }

        let fileURL = fileURLForDay(date)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

        // Build append-content
        var content = ""
        if !fileExists {
            // Ny dag — start med dato-header
            content += "# \(Self.dayFormatter.string(from: date))\n\n"
        }
        content += "## \(Self.timeFormatter.string(from: date))\n\(trimmed)\n\n"

        do {
            if fileExists {
                // Append til eksisterende fil
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                if let data = content.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                // Opret ny fil med header + entry
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            log.info("Journal-entry appendet til \(fileURL.lastPathComponent, privacy: .public) (\(trimmed.count, privacy: .public) chars)")
        } catch {
            log.warning("Kunne ikke skrive journal: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returnér fil-URL for en given dag.
    public func fileURLForDay(_ date: Date) -> URL {
        let dayString = Self.dayFormatter.string(from: date)
        return directory.appendingPathComponent("\(dayString).md")
    }

    /// Åbn dagens journal-fil i Finder eller default markdown-editor.
    public func revealInFinder(date: Date = Date()) {
        let url = fileURLForDay(date)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Hvis ingen fil endnu, vis bare mappen
            NSWorkspace.shared.open(directory)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
