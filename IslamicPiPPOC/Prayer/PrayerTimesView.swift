import SwiftUI
import PrayerTimes

/// Today's prayer times for the saved place: the next prayer with the time left, the day's
/// list, the place and calculation settings, the Qibla, and the floating window.
struct PrayerTimesView: View {
    @ObservedObject private var model = PrayerModel.shared
    @Environment(\.isPresented) private var isPresented
    @State private var pip: ReaderPiP?
    @State private var choosingPlace = false

    var body: some View {
        List {
            if let schedule = model.schedule, let place = model.place {
                // Redrawn every second so the time left and the current prayer follow the clock.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    times(schedule: schedule, place: place, now: context.date)
                }
                Section {
                    NavigationLink {
                        QiblaView()
                    } label: {
                        Label("اتجاه القبلة", systemImage: "location.north.line")
                    }
                    if let pip {
                        PiPEntryView(pip: pip, startTitle: "المواقيت في نافذة عائمة")
                    }
                } footer: {
                    Text("النافذة العائمة تعرض الصلاة القادمة والوقت المتبقي بخط كبير، وتحتها مواقيت اليوم. التقديم والرجوع ينتقلان بين الأيام، حتى ستة أيام قادمة.")
                }
                settings(place: place)
            } else {
                PrayerPlaceSetup(model: model)
            }
        }
        .navigationTitle("مواقيت الصلاة")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .sheet(isPresented: $choosingPlace) {
            NavigationStack {
                List { PrayerPlaceSetup(model: model) { choosingPlace = false } }
                    .navigationTitle("المكان")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("إغلاق") { choosingPlace = false }
                        }
                    }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .onAppear(perform: makePiP)
        .onChange(of: model.place) { makePiP() }
        .onDisappear {
            // Closed (not another tab): its PiP closes too.
            if !isPresented { pip?.screenClosed() }
        }
    }

    private func makePiP() {
        if pip == nil, let provider = model.pipProvider() { pip = ReaderPiP(provider: provider) }
    }

    @ViewBuilder
    private func times(schedule: PrayerSchedule, place: PrayerPlace, now: Date) -> some View {
        let zone = schedule.timeZone
        if let day = schedule.day(containing: now) {
            let current = schedule.current(at: now)
            Section {
                if let next = schedule.next(after: now) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("الصلاة القادمة")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(next.prayer.arabicName)
                                .font(.largeTitle.bold())
                            Spacer()
                            Text(clock(next.time, zone))
                                .font(.title2.monospacedDigit())
                        }
                        Text(PrayerFormat.remaining(from: now, to: next.time))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("الصلاة القادمة \(next.prayer.arabicName) الساعة \(clock(next.time, zone))، \(PrayerFormat.remaining(from: now, to: next.time))")
                }
            } header: {
                Text("\(PrayerFormat.gregorian(now, timeZone: zone)) · \(PrayerFormat.hijri(now, timeZone: zone))")
            }

            Section {
                ForEach(Prayer.allCases, id: \.self) { prayer in
                    let entry = (prayer: prayer, time: day.time(of: prayer))
                    let isCurrent = prayer == current
                    HStack {
                        Label(entry.prayer.arabicName, systemImage: icon(entry.prayer))
                            .fontWeight(isCurrent ? .bold : .regular)
                            .foregroundStyle(entry.prayer.isPrayer ? .primary : .secondary)
                        Spacer()
                        if isCurrent {
                            Text("الآن")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                        Text(clock(entry.time, zone))
                            .monospacedDigit()
                            .fontWeight(isCurrent ? .bold : .regular)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("اليوم في \(place.name)")
            }
        } else {
            Section {
                Text("لا يمكن حساب المواقيت لهذا المكان في هذا اليوم (الشمس لا تغيب أو لا تشرق).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func settings(place: PrayerPlace) -> some View {
        Section {
            Button {
                choosingPlace = true
            } label: {
                LabeledContent("المكان", value: place.name)
            }
            .foregroundStyle(.primary)
            Picker("طريقة الحساب", selection: $model.parameters.method) {
                ForEach(CalculationMethod.allCases, id: \.self) { method in
                    Text(method.arabicName).tag(method)
                }
            }
            Picker("العصر", selection: $model.parameters.asr) {
                ForEach(AsrSchool.allCases, id: \.self) { school in
                    Text(school.arabicName).tag(school)
                }
            }
            Toggle("نظام 24 ساعة", isOn: $model.twentyFourHour)
        } header: {
            Text("الإعدادات")
        } footer: {
            Text("المواقيت تُحسب على جهازك من إحداثيات المكان، وقد تختلف دقائق عن تقويم مسجدك. اختر الطريقة المعتمدة في بلدك.")
        }
    }

    private func clock(_ date: Date, _ zone: TimeZone) -> String {
        PrayerFormat.clock(date, timeZone: zone, twentyFourHour: model.twentyFourHour)
    }

    private func icon(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return "sun.haze"
        case .sunrise: return "sunrise"
        case .dhuhr: return "sun.max"
        case .asr: return "sun.min"
        case .maghrib: return "sunset"
        case .isha: return "moon.stars"
        }
    }
}

/// Where the times are for: the device's location, or a city from the list.
struct PrayerPlaceSetup: View {
    @ObservedObject var model: PrayerModel
    var chosen: () -> Void = {}

    var body: some View {
        Section {
            Button {
                model.useCurrentLocation()
            } label: {
                HStack {
                    Label("استخدام موقعي الحالي", systemImage: "location")
                    Spacer()
                    if model.locationState == .locating { ProgressView() }
                }
            }
            .disabled(model.locationState == .locating)
            switch model.locationState {
            case .denied:
                Text("الوصول إلى الموقع غير مسموح. يمكنك السماح به من إعدادات iPhone، أو اختيار مدينة من القائمة.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed:
                Text("تعذّر تحديد الموقع. حاول مرة أخرى، أو اختر مدينة من القائمة.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        } footer: {
            Text("يُقرأ الموقع مرة واحدة ويُحفظ على جهازك فقط، ولا يُرسل إلى أي مكان.")
        }
        .onChange(of: model.place) { _, place in
            if place?.isCurrentLocation == true { chosen() }
        }

        Section("أو اختر مدينة") {
            ForEach(PrayerCities.all, id: \.name) { city in
                Button {
                    model.choose(city)
                    chosen()
                } label: {
                    HStack {
                        Text(city.name)
                        Spacer()
                        if model.place == city { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}
