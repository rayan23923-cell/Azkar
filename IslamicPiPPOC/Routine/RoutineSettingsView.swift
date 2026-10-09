import SwiftUI
import ContentKit

/// The optional daily routine, saved on the device.
@MainActor
final class RoutineModel: ObservableObject {
    @Published var routine: DailyRoutine {
        didSet { store.routine = routine }
    }
    private let store: DailyRoutineStore

    init(store: DailyRoutineStore = DailyRoutineStore()) {
        self.store = store
        routine = store.routine
    }
}

/// Turn the routine on, pick its steps and their order. Off by default; when off, Home shows
/// nothing of it.
struct RoutineSettingsView: View {
    @ObservedObject var model: RoutineModel

    var body: some View {
        List {
            Section {
                Toggle("إظهار الورد في الرئيسية", isOn: $model.routine.isEnabled)
            } footer: {
                Text("قائمة هادئة لما تحب قراءته كل يوم، تظهر في الرئيسية وتُعلَّم بما أُنجز اليوم فقط. لا عدّ للأيام المتتالية ولا تذكير بما فات.")
            }
            if model.routine.isEnabled {
                Section {
                    ForEach(model.routine.entries, id: \.step) { entry in
                        Toggle(entry.step.arabicTitle, isOn: binding(for: entry.step))
                    }
                    .onMove { model.routine.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("الخطوات وترتيبها")
                } footer: {
                    Text("اضغط «تعديل» ثم اسحب لتغيير الترتيب. للتذكير بأذكار الصباح والمساء استخدم قسم «التذكير» في الإعدادات.")
                }
            }
        }
        .navigationTitle("الورد اليومي")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.routine.isEnabled { EditButton() }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func binding(for step: DailyRoutine.Step) -> Binding<Bool> {
        Binding(get: { model.routine.entries.first { $0.step == step }?.isOn ?? false },
                set: { model.routine.set(step, on: $0) })
    }
}
