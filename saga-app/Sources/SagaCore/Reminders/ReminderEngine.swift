import Foundation
import OSLog
import UserNotifications

/// Skemalægger lokale macOS-notifikationer (UNUserNotificationCenter) baseret
/// på naturligt-sprog reminders parset af LLM. ObservableObject så Settings-UI
/// kan vise upcoming reminders.
@MainActor
public final class ReminderEngine: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "reminders")
    private let center = UNUserNotificationCenter.current()
    private let storageKey = "reminders.scheduled"

    @Published public private(set) var scheduled: [ScheduledReminder] = []
    @Published public private(set) var permissionGranted: Bool = false

    public init() {
        load()
        Task { await refreshPermissionStatus() }
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

    /// Skemalægger en reminder. Returnerer fejl hvis trigger er i fortiden eller
    /// hvis bruger ikke har granted notification-permission.
    public func schedule(title: String, body: String, fireAt: Date) async throws -> ScheduledReminder {
        guard await requestPermissionIfNeeded() else {
            throw ReminderError.permissionDenied
        }
        guard fireAt > Date() else {
            throw ReminderError.fireDateInPast(fireAt)
        }

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
        log.info("Skemalagt: \(title, privacy: .public) @ \(fireAt, privacy: .public)")

        let reminder = ScheduledReminder(id: id, title: title, body: body, fireAt: fireAt, createdAt: Date())
        scheduled.insert(reminder, at: 0)
        persist()
        return reminder
    }

    public func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        scheduled.removeAll { $0.id == id }
        persist()
    }

    public func clearAll() {
        let ids = scheduled.map { $0.id }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        scheduled.removeAll()
        persist()
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

public struct ScheduledReminder: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireAt: Date
    public let createdAt: Date

    public var hasFired: Bool { fireAt < Date() }
    public var timeUntilFire: TimeInterval { fireAt.timeIntervalSinceNow }

    public init(id: String, title: String, body: String, fireAt: Date, createdAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
        self.createdAt = createdAt
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

public enum ReminderError: Error, LocalizedError {
    case permissionDenied
    case fireDateInPast(Date)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifikations-adgang mangler. Tillad i System Settings → Notifications → Saga."
        case .fireDateInPast(let date):
            return "Tidspunktet (\(date)) er allerede passeret."
        case .parseFailed(let raw):
            return "Kunne ikke forstå tidsangivelsen: '\(raw)'"
        }
    }
}
