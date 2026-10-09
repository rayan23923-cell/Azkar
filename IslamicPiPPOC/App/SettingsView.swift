import SwiftUI
import UIKit
import ContentKit
import QuranReading
import HisnReading
import PiPCore
import PiPRendering

/// The app's appearance setting, applied at the root.
enum AppAppearance: String, CaseIterable {
    case system, light, dark

    static let key = "app.appearance"

    var title: String {
        switch self {
        case .system: return "حسب النظام"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App settings. Arabic, right to left, system styles only.
struct SettingsView: View {
    @ObservedObject var reminders: ReminderController
    @AppStorage(HisnSettings.hapticsKey) private var hapticsEnabled = true
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system
    @AppStorage("quran.textSize") private var quranTextSize: Double = 26
    @AppStorage("adhkar.textSize") private var adhkarTextSize: Double = 24
    @AppStorage(PiPAvailability.settingKey) private var pipEnabled = true
    @AppStorage(PiPLayout.orientationKey) private var pipOrientation: PiPLayout.Orientation = .landscape
    @ObservedObject private var favorites = AppServices.shared.favorites
    @State private var confirmsReset = false
    @State private var confirmsFavorites = false
    @State private var notice: String?

    /// This build declares the PiP background mode (see docs/UNIFIED_PIP.md).
    private var pipInBuild: Bool { AppServices.shared.pip.availability.backgroundModeDeclared }

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

            Section("المظهر") {
                Picker("المظهر", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("الاهتزاز", isOn: $hapticsEnabled)
                VStack(alignment: .leading) {
                    Text("حجم خط القرآن: \(Int(quranTextSize))")
                    Slider(value: $quranTextSize, in: 18...44, step: 2)
                        .accessibilityLabel("حجم خط القرآن")
                        .accessibilityValue("\(Int(quranTextSize))")
                }
                VStack(alignment: .leading) {
                    Text("حجم خط الأذكار: \(Int(adhkarTextSize))")
                    Slider(value: $adhkarTextSize, in: 16...40, step: 2)
                        .accessibilityLabel("حجم خط الأذكار")
                        .accessibilityValue("\(Int(adhkarTextSize))")
                }
            } header: {
                Text("القراءة")
            } footer: {
                Text("يكبر الخط أيضاً مع حجم النص في إعدادات النظام.")
            }

            Section {
                LabeledContent("التلاوات الصوتية", value: "غير متاحة")
                if pipInBuild {
                    Toggle("العرض العائم", isOn: $pipEnabled)
                        .onChange(of: pipEnabled) { _, enabled in AppServices.shared.pip.setUserEnabled(enabled) }
                    Picker("اتجاه النافذة العائمة", selection: $pipOrientation) {
                        ForEach(PiPLayout.Orientation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if pipOrientation.layout != AppServices.shared.pipLayout {
                        Text("يُطبَّق الاتجاه الجديد بعد إغلاق التطبيق وفتحه من جديد.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(pipInBuild ? "الصوت والعرض العائم" : "الصوت")
            } footer: {
                Text(pipInBuild
                     ? "يعرض الآية أو الذكر أو الدعاء الحالي في نافذة عائمة فوق التطبيقات الأخرى. التشغيل والإيقاف يقلّبان الصفحات، والتقديم والرجوع ينتقلان بين العناصر، وفي حصن المسلم يعدّ التقديم التكرار. يُفتح من زر «نافذة عائمة» في كل قسم. لا تُضمَّن تسجيلات صوتية في هذا الإصدار حتى تُستوفى حقوقها."
                     : "لا تُضمَّن تسجيلات صوتية في هذا الإصدار حتى تُستوفى حقوقها.")
            }

            Section("البيانات") {
                Button("مسح مواضع القراءة والتقدّم", role: .destructive) { confirmsReset = true }
                Button("مسح المفضلة (\(favorites.entries.count))", role: .destructive) { confirmsFavorites = true }
                    .disabled(favorites.entries.isEmpty)
            }

            Section {
                NavigationLink("حول التطبيق والمصادر والخصوصية") { AboutView() }
            }
        }
        .navigationTitle("الإعدادات")
        .transientNotice($notice)
        .confirmationDialog("مسح مواضع القراءة وتقدّم اليوم في كل الأقسام؟", isPresented: $confirmsReset,
                            titleVisibility: .visible) {
            Button("مسح", role: .destructive) {
                UserDefaultsQuranPositionStore().clear()
                UserDefaultsHisnReadingPositionStore().clear()
                AppServices.shared.devotionalPositions.clearAll()
                AppServices.shared.dailyProgress.clear()
                showNotice("مُسحت مواضع القراءة", in: $notice)
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لا يمكن التراجع عن ذلك. لا تُمسح المفضلة ولا إعدادات التذكير.")
        }
        .confirmationDialog("مسح كل المفضلة والعلامات؟", isPresented: $confirmsFavorites, titleVisibility: .visible) {
            Button("مسح", role: .destructive) {
                favorites.clear()
                showNotice("مُسحت المفضلة", in: $notice)
            }
            Button("إلغاء", role: .cancel) {}
        }
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
