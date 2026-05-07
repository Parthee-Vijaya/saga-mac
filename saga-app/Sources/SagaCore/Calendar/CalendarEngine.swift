import EventKit
import Foundation
import OSLog

/// Opretter EKEvent-entries i Apple Kalender via EventKit. Synker til iPhone +
/// Watch + andre Macs via iCloud. Permission-flow parallel til ReminderEngine
/// men separat — Reminders + Calendar har hver deres TCC-prompt.
@MainActor
public final class CalendarEngine: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "calendar")
    private let eventStore = EKEventStore()
    private let calendarIDKey = "calendar.defaultCalendarIdentifier"
    private let useAppleKey = "calendar.useApple"

    @Published public private(set) var permissionGranted: Bool = false
    @Published public private(set) var availableCalendars: [CalendarChoice] = []

    /// Hvis true (default): voice-events oprettes i Apple Calendar.
    /// Hvis false: CalendarMode er disabled og falder tilbage til pure dictation.
    @Published public var useAppleCalendar: Bool {
        didSet {
            UserDefaults.standard.set(useAppleCalendar, forKey: useAppleKey)
        }
    }

    /// EKCalendar-identifier hvor nye events gemmes. Hvis nil bruges
    /// `eventStore.defaultCalendarForNewEvents`.
    @Published public var calendarID: String? {
        didSet {
            UserDefaults.standard.set(calendarID, forKey: calendarIDKey)
        }
    }

    public init() {
        self.useAppleCalendar = UserDefaults.standard.object(forKey: useAppleKey) as? Bool ?? true
        self.calendarID = UserDefaults.standard.string(forKey: calendarIDKey)
        Task { await refreshPermissionStatus() }
    }

    // MARK: - Permission

    public func requestPermission() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                permissionGranted = granted
                if granted { await refreshAvailableCalendars() }
                return granted
            } catch {
                log.error("Calendar authorization fejlede: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .fullAccess:
            permissionGranted = true
            await refreshAvailableCalendars()
            return true
        case .writeOnly:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                permissionGranted = granted
                if granted { await refreshAvailableCalendars() }
                return granted
            } catch {
                log.error("Calendar upgrade til full access fejlede: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied, .restricted:
            permissionGranted = false
            return false
        @unknown default:
            return false
        }
    }

    public func refreshPermissionStatus() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        permissionGranted = (status == .fullAccess)
        if permissionGranted {
            await refreshAvailableCalendars()
        }
    }

    private func refreshAvailableCalendars() async {
        let calendars = eventStore.calendars(for: .event)
        availableCalendars = calendars
            .filter { $0.allowsContentModifications }  // skip read-only kalendere (fx feriedage)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
    }

    // MARK: - Create event

    /// Opretter EKEvent og gemmer i den valgte (eller default) kalender.
    /// Returnerer en CreatedEvent-snapshot der kan bruges til confirmation.
    public func createEvent(
        title: String,
        start: Date,
        end: Date,
        attendees: [String],
        notes: String
    ) async throws -> CreatedEvent {
        guard useAppleCalendar else {
            throw CalendarError.disabled
        }
        guard await requestPermission() else {
            throw CalendarError.permissionDenied
        }
        guard end > start else {
            throw CalendarError.invalidDuration
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end

        // Inkluder deltagere i notes — EventKit tillader ikke at skrive participants
        // direkte (kun via system-invites), så vi lægger dem i notes-feltet for at
        // bevare informationen ved cursor-confirmation.
        var combinedNotes = notes
        if !attendees.isEmpty {
            let prefix = "Deltagere: \(attendees.joined(separator: ", "))"
            combinedNotes = combinedNotes.isEmpty ? prefix : "\(prefix)\n\n\(notes)"
        }
        event.notes = combinedNotes.isEmpty ? nil : combinedNotes

        let chosen = calendarID.flatMap { eventStore.calendar(withIdentifier: $0) }
            ?? eventStore.defaultCalendarForNewEvents
            ?? availableCalendars.first.flatMap { eventStore.calendar(withIdentifier: $0.id) }
        guard let calendar = chosen else {
            throw CalendarError.noCalendarAvailable
        }
        event.calendar = calendar

        // Standard-alarm: 10 min før mødet starter (matcher Apple's default i Calendar.app)
        event.addAlarm(EKAlarm(relativeOffset: -600))

        try eventStore.save(event, span: .thisEvent, commit: true)
        log.info("Oprettet event '\(title, privacy: .public)' i kalender '\(calendar.title, privacy: .public)' \(start, privacy: .public) — \(end, privacy: .public)")

        return CreatedEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: title,
            start: start,
            end: end,
            calendarTitle: calendar.title
        )
    }
}

// MARK: - Models

public struct CalendarChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String

    public var displayName: String {
        "\(title) — \(sourceTitle)"
    }
}

public struct CreatedEvent: Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarTitle: String

    public var formattedSummary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        let now = Date()
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: now) {
            formatter.dateFormat = "'i dag kl.' HH:mm"
        } else if cal.isDate(start, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now) ?? now) {
            formatter.dateFormat = "'i morgen kl.' HH:mm"
        } else {
            formatter.dateFormat = "EEEE d. MMM 'kl.' HH:mm"
        }
        return "\(title) \(formatter.string(from: start))"
    }
}

public enum CalendarError: Error, LocalizedError {
    case disabled
    case permissionDenied
    case invalidDuration
    case noCalendarAvailable
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Apple Kalender er slukket i Saga's settings."
        case .permissionDenied:
            return "Saga mangler adgang til Apple Kalender. Tillad i System Settings → Privacy → Calendars."
        case .invalidDuration:
            return "Slut-tidspunkt skal være efter start-tidspunkt."
        case .noCalendarAvailable:
            return "Ingen skrivbar kalender tilgængelig. Opret en i Apple Kalender først."
        case .parseFailed(let raw):
            return "Kunne ikke forstå kalender-tekst: '\(raw)'"
        }
    }
}
