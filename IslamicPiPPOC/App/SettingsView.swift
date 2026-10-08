import SwiftUI
import UIKit
import ContentKit

/// App settings. Arabic, right to left, system styles only.
struct SettingsView: View {
    @ObservedObject var reminders: ReminderController
    @AppStorage(HisnSettings.hapticsKey) private var hapticsEnabled = true

    var body: some View {
        Form {
            Section {
                ForEach(ReminderKind.allCases, id: \.self) { kind in
                    ReminderRow(kind: kind, reminders: reminders)
                }
                if reminders.authorization == .denied && reminders.settings.anyEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("الإشعارات غير مسموح بها لهذا التطبيق، فلن يصل التذكير.")
                            .font(.footnote)
                        Button("فتح إعدادات النظام") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote)
                    }
                }
                if let error = reminders.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("التذكير")
            } footer: {
                Text("تذكير يومي على هذا الجهاز فقط، بالوقت المحلي.")
            }

            Section("القراءة") {
                Toggle("الاهتزاز", isOn: $hapticsEnabled)
            }
        }
        .navigationTitle("الإعدادات")
        .task { await reminders.refreshAuthorization() }
    }
}

private struct ReminderRow: View {
    let kind: ReminderKind
    @ObservedObject var reminders: ReminderController

    var body: some View {
        let reminder = reminders.settings[kind]
        VStack(alignment: .leading) {
            Toggle(kind.title, isOn: Binding(
                get: { reminder.isEnabled },
                set: { enabled in Task { await reminders.setEnabled(enabled, for: kind) } }
            ))
            if reminder.isEnabled {
                DatePicker("الوقت", selection: Binding(
                    get: { Self.date(hour: reminder.hour, minute: reminder.minute) },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        Task { await reminders.setTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0, for: kind) }
                    }
                ), displayedComponents: .hourAndMinute)
                .accessibilityLabel("وقت تذكير \(kind.title)")
            }
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
