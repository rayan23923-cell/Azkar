import Foundation
import ContentKit
import QuranReading
import HisnReading
import AdhkarReading

/// «أكمل من حيث توقفت»: the place read last, across the Quran, Hisn Al-Muslim, the adhkar and
/// the duas, from the positions each reader already saves (with the time it saved them).
struct ResumeOffer: Equatable {
    let point: ResumePoint
    let title: String
    let detail: String

    var systemImage: String {
        switch point.section {
        case .quran: return "book"
        case .hisn: return "shield"
        case .adhkar: return "hands.sparkles"
        case .dua: return "hand.raised"
        }
    }
}

@MainActor
enum ResumeFinder {
    /// The most recent valid place (`ResumePoint.mostRecent`); nil when nothing is saved.
    /// A position whose content no longer exists is skipped.
    static func latest() async -> ResumeOffer? {
        let offers = await all()
        guard let point = ResumePoint.mostRecent(offers.map(\.point)) else { return nil }
        return offers.first { $0.point == point }
    }

    static func all() async -> [ResumeOffer] {
        var offers: [ResumeOffer] = []
        let content = AppServices.shared.content
        if let quran = try? await content.quran(),
           let position = UserDefaultsQuranPositionStore().validPosition(in: quran.library),
           let surah = quran.library.surah(position.surah) {
            offers.append(ResumeOffer(
                point: ResumePoint(section: .quran, target: .quranVerse(surah: position.surah, ayah: position.ayah),
                                   container: nil, savedAt: position.savedAt),
                title: "القرآن الكريم: \(surah.fullArabicName)",
                detail: "الآية \(position.ayah) من \(surah.ayahCount)"))
        }
        if let library = try? await content.hisn(),
           let position = HisnResume.position(in: UserDefaultsHisnReadingPositionStore(), library: library),
           let chapter = library.chapter(id: position.chapterId) {
            offers.append(ResumeOffer(
                point: ResumePoint(section: .hisn, target: .hisnItem(position.itemId),
                                   container: .hisnSection(position.chapterId), savedAt: position.savedAt),
                title: "حصن المسلم: \(chapter.titleArabic)",
                detail: "الذكر \(position.itemIndex + 1) من \(chapter.items.count)"))
        }
        if let adhkar = try? await content.adhkar().library {
            for (ref, position) in AppServices.shared.devotionalPositions.all() {
                guard let collection = adhkar.collection(ref),
                      let index = collection.items.firstIndex(where: { $0.ref == position.item }) else { continue }
                let isDua = collection.kind == .dua
                offers.append(ResumeOffer(
                    point: ResumePoint(section: isDua ? .dua : .adhkar, target: position.item, container: ref,
                                       savedAt: position.savedAt),
                    title: collection.title,
                    detail: "\(isDua ? "الدعاء" : "الذكر") \(index + 1) من \(collection.items.count)"))
            }
        }
        return offers
    }
}
