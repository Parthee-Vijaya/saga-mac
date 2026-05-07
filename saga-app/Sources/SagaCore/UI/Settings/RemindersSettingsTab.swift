import SwiftUI

struct RemindersSettingsTab: View {
    @EnvironmentObject private var controller: SagaController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                appleRemindersCard
                listPickerCard
                fallbackPermissionCard
                scheduledListCard
                Divider().padding(.vertical, 4)
                appleCalendarCard
                calendarPickerCard
            }
            .padding(20)
        }
    }

    // MARK: - Apple Reminders (EventKit)

    private var appleRemindersCard: some View {
        SettingsCard(
            "Apple Reminders",
            footer: "Når aktiv: reminders gemmes i Apple Reminders og synker til iPhone + Watch via iCloud. Du kan markere dem færdige hvor som helst."
        ) {
            SettingsRow(
                "Brug Apple Reminders",
                subtitle: controller.reminders.useAppleReminders
                    ? "Aktiv — synker til iPhone"
                    : "Slukket — bruger lokal notification (kun denne Mac)"
            ) {
                Toggle("", isOn: Binding(
                    get: { controller.reminders.useAppleReminders },
                    set: { newValue in
                        controller.reminders.useAppleReminders = newValue
                        if newValue {
                            Task { _ = await controller.reminders.requestEventKitPermission() }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 10) {
                Image(systemName: controller.reminders.eventKitPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(controller.reminders.eventKitPermissionGranted ? .green : .orange)
                Text(controller.reminders.eventKitPermissionGranted ? "EventKit-adgang tilladt" : "EventKit-adgang mangler")
                    .font(.system(size: 13))
                Spacer()
                if !controller.reminders.eventKitPermissionGranted {
                    Button("Spørg") {
                        Task { _ = await controller.reminders.requestEventKitPermission() }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var listPickerCard: some View {
        if controller.reminders.useAppleReminders, controller.reminders.eventKitPermissionGranted, !controller.reminders.availableLists.isEmpty {
            SettingsCard(
                "Default reminder-liste",
                footer: "Hvor nye reminders gemmes. Listen synkes typisk via iCloud."
            ) {
                SettingsRow(
                    "Liste",
                    subtitle: "Vælg den liste hvor 'mind mig om...' havner"
                ) {
                    Picker("", selection: Binding(
                        get: { controller.reminders.reminderListID ?? "__default__" },
                        set: { newValue in
                            controller.reminders.reminderListID = newValue == "__default__" ? nil : newValue
                        }
                    )) {
                        Text("Standard").tag("__default__")
                        ForEach(controller.reminders.availableLists) { list in
                            Text(list.displayName).tag(list.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }
            }
        }
    }

    private var fallbackPermissionCard: some View {
        SettingsCard(
            "Lokal notification (fallback)",
            footer: "Bruges hvis Apple Reminders er slukket eller EventKit-adgang mangler. Notifikationen vises kun på denne Mac."
        ) {
            HStack(spacing: 10) {
                Image(systemName: controller.reminders.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(controller.reminders.permissionGranted ? .green : .orange)
                Text(controller.reminders.permissionGranted ? "Tilladt" : "Mangler")
                    .font(.system(size: 13))
                Spacer()
                if !controller.reminders.permissionGranted {
                    Button("Spørg") {
                        Task { _ = await controller.reminders.requestPermissionIfNeeded() }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Apple Calendar (EventKit)

    private var appleCalendarCard: some View {
        SettingsCard(
            "Apple Kalender",
            footer: "Når aktiv: voice-events oprettes i Apple Kalender. Sig 'book møde med Lars i morgen kl 14 til 15 om Q3'."
        ) {
            SettingsRow(
                "Brug Apple Kalender",
                subtitle: controller.appleCalendar.useAppleCalendar
                    ? "Aktiv — voice-events havner i kalender"
                    : "Slukket — kalender-mode er disabled"
            ) {
                Toggle("", isOn: Binding(
                    get: { controller.appleCalendar.useAppleCalendar },
                    set: { newValue in
                        controller.appleCalendar.useAppleCalendar = newValue
                        if newValue {
                            Task { _ = await controller.appleCalendar.requestPermission() }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 10) {
                Image(systemName: controller.appleCalendar.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(controller.appleCalendar.permissionGranted ? .green : .orange)
                Text(controller.appleCalendar.permissionGranted ? "Calendar-adgang tilladt" : "Calendar-adgang mangler")
                    .font(.system(size: 13))
                Spacer()
                if !controller.appleCalendar.permissionGranted {
                    Button("Spørg") {
                        Task { _ = await controller.appleCalendar.requestPermission() }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var calendarPickerCard: some View {
        if controller.appleCalendar.useAppleCalendar, controller.appleCalendar.permissionGranted, !controller.appleCalendar.availableCalendars.isEmpty {
            SettingsCard(
                "Default kalender",
                footer: "Hvor nye events gemmes. Vælg fx 'Arbejde' eller 'Personlig' afhængig af hvor du vil have voice-bookede møder."
            ) {
                SettingsRow(
                    "Kalender",
                    subtitle: "Vælg den kalender hvor 'book møde'-events havner"
                ) {
                    Picker("", selection: Binding(
                        get: { controller.appleCalendar.calendarID ?? "__default__" },
                        set: { newValue in
                            controller.appleCalendar.calendarID = newValue == "__default__" ? nil : newValue
                        }
                    )) {
                        Text("Standard").tag("__default__")
                        ForEach(controller.appleCalendar.availableCalendars) { cal in
                            Text(cal.displayName).tag(cal.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }
            }
        }
    }

    private var scheduledListCard: some View {
        SettingsCard(
            "Skemalagte (\(controller.reminders.scheduled.count))",
            footer: "Sig 'mind mig om at ringe til Lars i morgen kl 14' for at oprette en."
        ) {
            if controller.reminders.scheduled.isEmpty {
                HStack {
                    Spacer()
                    Text("Ingen kommende reminders")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(controller.reminders.scheduled) { reminder in
                        ReminderRow(reminder: reminder)
                            .environmentObject(controller)
                    }
                    HStack {
                        Spacer()
                        Button("Ryd alt", role: .destructive) {
                            controller.reminders.clearAll()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct ReminderRow: View {
    @EnvironmentObject private var controller: SagaController
    let reminder: ScheduledReminder

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: reminder.hasFired ? "bell.slash" : "bell.fill")
                .foregroundColor(reminder.hasFired ? .secondary : Color(red: 0.20, green: 0.55, blue: 0.95))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.system(size: 13, weight: .medium))
                    backendBadge
                }
                Text(reminder.formattedFireDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !reminder.body.isEmpty {
                    Text(reminder.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                controller.reminders.cancel(id: reminder.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var backendBadge: some View {
        switch reminder.backend {
        case .appleReminders:
            Text("Apple")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.18))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
        case .localNotification:
            Text("Lokal")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
        }
    }
}
