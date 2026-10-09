import SwiftUI
import UIKit
import PrayerTimes

/// The Qibla: an arrow that turns with the device toward the Kaaba, the bearing from north and
/// the distance. Without a compass (or before it reads), the bearing alone, to use with any
/// compass.
struct QiblaView: View {
    @ObservedObject private var model = PrayerModel.shared
    @StateObject private var compass = QiblaCompass()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Within this many degrees the device faces the Qibla.
    private static let aligned = 5.0

    var body: some View {
        Group {
            if let place = model.place {
                content(place: place)
            } else {
                List { PrayerPlaceSetup(model: model) }
            }
        }
        .navigationTitle("اتجاه القبلة")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .onAppear {
            compass.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            compass.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func content(place: PrayerPlace) -> some View {
        let bearing = Qibla.bearing(from: place.coordinates)
        let distance = Qibla.distance(from: place.coordinates)
        let reading = compass.reading
        let turn = reading.map { Qibla.turn(bearing: bearing, heading: $0.degrees) }
        let facing = turn.map { abs($0) <= Self.aligned } ?? false

        return ScrollView {
            VStack(spacing: 24) {
                // The dial is drawn left-to-right: east is to the right whatever the language.
                dial(turn: turn, facing: facing)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    if let turn {
                        Text(guidance(turn: turn, facing: facing))
                            .font(.title3.bold())
                            .foregroundStyle(facing ? Color.green : Color.primary)
                    }
                    Text("\(Int(bearing.rounded()))° من الشمال (\(Qibla.compassPoint(bearing)))")
                        .font(.headline.monospacedDigit())
                    Text("المسافة إلى الكعبة نحو \(Int(distance.rounded())) كم")
                        .foregroundStyle(.secondary)
                    Text(place.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                notes(reading: reading)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .sensoryFeedback(.success, trigger: facing) { _, now in now }
    }

    private func dial(turn: Double?, facing: Bool) -> some View {
        // The dial turns so north points north; the Qibla arrow sits at the bearing on it.
        let heading = compass.reading?.degrees ?? 0
        let bearing = model.place.map { Qibla.bearing(from: $0.coordinates) } ?? 0
        return ZStack {
            Circle()
                .stroke(.secondary.opacity(0.35), lineWidth: 2)
            ForEach(0..<72) { tick in
                Capsule()
                    .fill(.secondary.opacity(tick % 18 == 0 ? 0.9 : 0.35))
                    .frame(width: 2, height: tick % 18 == 0 ? 14 : 7)
                    .offset(y: -133)
                    .rotationEffect(.degrees(Double(tick) * 5))
            }
            ForEach(Array(["ش", "ق", "ج", "غ"].enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.headline)
                    .foregroundStyle(index == 0 ? Color.red : Color.secondary)
                    .rotationEffect(.degrees(heading - Double(index) * 90))
                    .offset(y: -112)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Image(systemName: "location.north.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 54)
                .foregroundStyle(facing ? Color.green : Color.accentColor)
                .offset(y: -60)
                .rotationEffect(.degrees(bearing))
            Image(systemName: "building.columns.fill")
                .font(.title2)
                .foregroundStyle(facing ? Color.green : Color.primary)
                .rotationEffect(.degrees(heading - bearing))
                .offset(y: -162)
                .rotationEffect(.degrees(bearing))
                .opacity(compass.reading == nil ? 0 : 1)
        }
        .rotationEffect(.degrees(-heading))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: heading)
        .frame(width: 280, height: 280)
        .padding(28)
        .accessibilityElement()
        .accessibilityLabel(turn.map { guidance(turn: $0, facing: facing) } ?? "اتجاه القبلة")
    }

    private func guidance(turn: Double, facing: Bool) -> String {
        if facing { return "أنت متّجه نحو القبلة" }
        let degrees = Int(abs(turn).rounded())
        return turn > 0 ? "استدر يميناً \(degrees)°" : "استدر يساراً \(degrees)°"
    }

    @ViewBuilder
    private func notes(reading: QiblaCompass.Reading?) -> some View {
        if !compass.isAvailable {
            Text("لا توجد بوصلة في هذا الجهاز. استخدم الزاوية أعلاه مع أي بوصلة: القبلة على هذه الزاوية من الشمال باتجاه عقارب الساعة.")
        } else if let reading {
            VStack(spacing: 6) {
                if let accuracy = reading.accuracy, accuracy > 20 {
                    Text("دقة البوصلة ضعيفة (±\(Int(accuracy))°). حرّك الجهاز على شكل الرقم 8 لمعايرتها.")
                } else if reading.accuracy == nil {
                    Text("البوصلة تحتاج معايرة: حرّك الجهاز على شكل الرقم 8.")
                }
                if !reading.isTrueNorth {
                    Text("الاتجاه من الشمال المغناطيسي، لأن الموقع غير مفعّل. قد يختلف بضع درجات عن الشمال الحقيقي.")
                }
                Text("أمسك الجهاز مستوياً، بعيداً عن المعادن والمغناطيس.")
            }
        } else {
            Text("جارٍ قراءة البوصلة…")
        }
    }
}
