import EventKit
import Foundation
import OSLog
import UserNotifications

/// Skemalægger reminders. To backends:
/// 1. **Apple Reminders** (default når permission grantet) — via EventKit, synker
///    til Reminders.app + iPhone + Watch. Bruger kan markere færdig hvor som helst.
/// 2. **Local notification** (fallback) — UNUserNotificationCenter, kun lokalt
///    på Mac'en, forsvinder ved sleep.
///
/// `useAppleReminders` toggles backend; persisteres i UserDefaults.
@MainActor
public final class ReminderEngine: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "reminders")
    private let center = UNUserNotificationCenter.current()
    private let eventStore = EKEventStore()
    private let storageKey = "reminders.scheduled"
    private let useAppleKey = "reminders.useApple"
    private let listIDKey = "reminders.defaultListIdentifier"

    @Published public private(set) var scheduled: [ScheduledReminder] = []
    @Published public private(set) var permissionGranted: Bool = false
    @Published public private(set) var eventKitPermissionGranted: Bool = false
    @Published public private(set) var availableLists: [ReminderList] = []

    /// Hvis true (default): brug EventKit/Apple Reminders. Hvis EventKit-permission
    /// er denied, falder vi automatisk tilbage til UNUserNotificationCenter.
    @Published public var useAppleReminders: Bool {
        didSet {
            UserDefaults.standard.set(useAppleReminders, forKey: useAppleKey)
        }
    }

    /// EKReminder-list-identifier hvor nye reminders gemmes. Hvis nil bruges
    /// `eventStore.defaultCalendarForNewReminders()`.
    @Published public var reminderListID: String? {
        didSet {
            UserDefaults.standard.set(reminderListID, forKey: listIDKey)
        }
    }

    public init() {
        // Default: EventKit ON. Bruger kan slå fra i Settings hvis de ikke vil have iPhone-sync.
        self.useAppleReminders = UserDefaults.standard.object(forKey: useAppleKey) as? Bool ?? true
        self.reminderListID = UserDefaults.standard.string(forKey: listIDKey)
        load()
        Task {
            await refreshPermissionStatus()
            await refreshEventKitStatus()
        }
    }

    public func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                permissionGranted = granted
                return granted
            } catch {
                log.error("Notification authorization fejlede: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .authorized, .provisional:
            permissionGranted = true
            return true
        case .denied:
            permissionGranted = false
            return false
        @unknown default:
            return false
        }
    }

    public func refreshPermissionStatus() async {
        let settings = await center.notificationSettings()
        permissionGranted = [.authorized, .provisional].contains(settings.authorizationStatus)
    }

    // MARK: - EventKit / Apple Reminders

    /// Spørg om EventKit Reminders-adgang. Returnerer true hvis grantet.
    /// macOS 14+: bruger `requestFullAccessToReminders()`. Pre-14 bruger
    /// deprecated `requestAccess(to:)` — Saga's deployment target er 15.0
    /// så vi behøver kun den nye API.
    public func requestEventKitPermission() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                eventKitPermissionGranted = granted
                if granted { await refreshAvailableLists() }
                return granted
            } catch {
                log.error("EventKit reminders authorization fejlede: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .fullAccess:
            eventKitPermissionGranted = true
            await refreshAvailableLists()
            return true
        case .writeOnly:
            // Ikke nok til at læse listen af kalendere — spørg om fuld adgang
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                eventKitPermissionGranted = granted
                if granted { await refreshAvailableLists() }
                return granted
            } catch {
                log.error("EventKit upgrade til full access fejlede: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied, .restricted:
            eventKitPermissionGranted = false
            return false
        @unknown default:
            return false
        }
    }

    public func refreshEventKitStatus() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        eventKitPermissionGranted = (status == .fullAccess)
        if eventKitPermissionGranted {
            await refreshAvailableLists()
        }
    }

    private func refreshAvailableLists() async {
        let calendars = eventStore.calendars(for: .reminder)
        availableLists = calendars.map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title)
        }
    }

    // MARK: - Schedule

    /// Skemalægger en reminder. Routes til EventKit hvis useAppleReminders er ON
    /// og permission grantet. Ellers fallback til UNUserNotificationCenter.
    /// Returnerer fejl hvis trigger er i fortiden eller ingen backend tilgængelig.
    public func schedule(title: String, body: String, fireAt: Date) async throws -> ScheduledReminder {
        guard fireAt > Date() else {
            throw ReminderError.fireDateInPast(fireAt)
        }

        // Foretrukken backend: EventKit (synker til iPhone)
        if useAppleReminders, await requestEventKitPermission() {
            return try createInRemindersApp(title: title, body: body, fireAt: fireAt)
        }

        // Fallback: lokal notification
        guard await requestPermissionIfNeeded() else {
            throw ReminderError.permissionDenied
        }

        return try await scheduleLocalNotification(title: title, body: body, fireAt: fireAt)
    }

    private func scheduleLocalNotification(title: String, body: String, fireAt: Date) async throws -> ScheduledReminder {
        let id = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sagaReminderId": id]

        let interval = fireAt.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try await center.add(request)
        log.info("Skemalagt local notification: \(title, privacy: .public) @ \(fireAt, privacy: .public)")

        let reminder = ScheduledReminder(
            id: id,
            title: title,
            body: body,
            fireAt: fireAt,
            createdAt: Date(),
            backend: .localNotification
        )
        scheduled.insert(reminder, at: 0)
        persist()
        return reminder
    }

    private func createInRemindersApp(title: String, body: String, fireAt: Date) throws -> ScheduledReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = body.isEmpty ? nil : body

        // Vælg liste: bruger-valgt → defaultCalendarForNewReminders → første tilgængelige
        let chosen = reminderListID.flatMap { eventStore.calendar(withIdentifier: $0) }
            ?? eventStore.defaultCalendarForNewReminders()
            ?? eventStore.calendars(for: .reminder).first
        guard let calendar = chosen else {
            throw ReminderError.eventKitNoListAvailable
        }
        reminder.calendar = calendar

        // dueDateComponents (vist i Reminders.app som "kl. 14:00") + alarm (notificerer)
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireAt
        )
        reminder.dueDateComponents = comps
        reminder.addAlarm(EKAlarm(absoluteDate: fireAt))

        try eventStore.save(reminder, commit: true)
        log.info("Skemalagt Apple Reminder: \(title, privacy: .public) @ \(fireAt, privacy: .public) i liste '\(calendar.title, privacy: .public)'")

        let scheduled = ScheduledReminder(
            id: reminder.calendarItemIdentifier,
            title: title,
            body: body,
            fireAt: fireAt,
            createdAt: Date(),
            backend: .appleReminders
        )
        self.scheduled.insert(scheduled, at: 0)
        persist()
        return scheduled
    }

    public func cancel(id: String) {
        // Find reminder for at vide hvilken backend
        guard let entry = scheduled.first(where: { $0.id == id }) else { return }
        switch entry.backend {
        case .localNotification:
            center.removePendingNotificationRequests(withIdentifiers: [id])
        case .appleReminders:
            // Slet fra EventKit hvis vi har permission
            if let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
                do {
                    try eventStore.remove(ekReminder, commit: true)
                } catch {
                    log.warning("Kunne ikke slette Apple Reminder \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        scheduled.removeAll { $0.id == id }
        persist()
    }

    public func clearAll() {
        for entry in scheduled {
            cancel(id: entry.id)
        }
    }

    /// Fjern reminders der er fyret (i fortiden) — bruges af UI til at holde listen ren.
    public func purgeFired() {
        let now = Date()
        scheduled.removeAll { $0.fireAt < now }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let decoded = try dec.decode([ScheduledReminder].self, from: data)
            scheduled = decoded.filter { $0.fireAt > Date().addingTimeInterval(-3600 * 24 * 7) }
        } catch {
            log.warning("Kunne ikke læse reminders: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(scheduled)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            log.warning("Kunne ikke gemme reminders: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Models

public enum ReminderBackend: String, Codable, Sendable {
    case localNotification
    case appleReminders
}

public struct ScheduledReminder: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireAt: Date
    public let createdAt: Date
    public let backend: ReminderBackend

    public var hasFired: Bool { fireAt < Date() }
    public var timeUntilFire: TimeInterval { fireAt.timeIntervalSinceNow }

    public init(
        id: String,
        title: String,
        body: String,
        fireAt: Date,
        createdAt: Date,
        backend: ReminderBackend = .localNotification
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
        self.createdAt = createdAt
        self.backend = backend
    }

    // Backwards-compat decode for entries gemt før backend-felt eksisterede
    private enum CodingKeys: String, CodingKey {
        case id, title, body, fireAt, createdAt, backend
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.body = try c.decode(String.self, forKey: .body)
        self.fireAt = try c.decode(Date.self, forKey: .fireAt)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.backend = try c.decodeIfPresent(ReminderBackend.self, forKey: .backend) ?? .localNotification
    }

    public var formattedFireDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        let now = Date()
        let cal = Calendar.current
        if cal.isDate(fireAt, inSameDayAs: now) {
            formatter.dateFormat = "'i dag kl.' HH:mm"
        } else if cal.isDate(fireAt, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now) ?? now) {
            formatter.dateFormat = "'i morgen kl.' HH:mm"
        } else {
            formatter.dateFormat = "EEEE d. MMM 'kl.' HH:mm"
        }
        return formatter.string(from: fireAt)
    }
}

public struct ReminderList: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String

    public var displayName: String {
        "\(title) — \(sourceTitle)"
    }
}

public enum ReminderError: Error, LocalizedError {
    case permissionDenied
    case fireDateInPast(Date)
    case parseFailed(String)
    case eventKitNoListAvailable

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifikations-adgang mangler. Tillad i System Settings → Notifications → Saga."
        case .fireDateInPast(let date):
            return "Tidspunktet (\(date)) er allerede passeret."
        case .parseFailed(let raw):
            return "Kunne ikke forstå tidsangivelsen: '\(raw)'"
        case .eventKitNoListAvailable:
            return "Ingen Reminders-lister tilgængelige. Opret en i Reminders.app først."
        }
    }
}
