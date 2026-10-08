#if HISN_AUDIO_FIXTURE
import Foundation
import IslamicCore

/// Device-test build only (compiled with `HISN_AUDIO_FIXTURE`, see the `build` CI job's
/// fixture IPA step). The production app does not contain this code or these files.
///
/// Reads `HisnAudioFixture/hisn_audio.device-test.json` and its synthetic test tone from the
/// app bundle and allows TEST_ONLY assets, so Hisn PiP and audio can be tested on a device
/// before any production recording exists. The tone is not a recitation.
enum HisnAudioFixture {
    static let notice = "نسخة اختبار: الصوت نغمة اختبار صناعية وليس تلاوة"

    static func repository(knownItemIds: Set<String>) -> HisnAudioRepository? {
        guard let directory = Bundle.main.url(forResource: "HisnAudioFixture", withExtension: nil),
              let manifest = try? Data(contentsOf: directory.appendingPathComponent("hisn_audio.device-test.json"))
        else { return nil }
        return BundledHisnAudioRepository(knownItemIds: knownItemIds, manifest: .data(manifest),
                                          audioDirectory: directory, allowedUsage: [.testOnly])
    }
}
#endif
