import SwiftUI

struct RemindersSettingsTab: View {
    @EnvironmentObject private var controller: SagaController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Notifikations-adgang",
                    footer: "Saga skemalægger reminders som lokale macOS-notifikationer."
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
            .padding(20)
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
                Text(reminder.title)
                    .font(.system(size: 13, weight: .medium))
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
}
