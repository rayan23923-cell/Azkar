import SwiftUI
import QuranText
import QuranReading

/// Sources, licences and privacy, shown in the app. The Tanzil notice is reproduced as its
/// terms require. Rights review of Hisn Al-Muslim is pending, and the page says so.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("الإصدار", value: version)
            }
            Section("الخصوصية") {
                Text("لا يجمع التطبيق أي بيانات ولا يرسلها. كل المحتوى مضمَّن في التطبيق ويعمل دون اتصال. تُحفظ مواضع القراءة والمفضلة وإعدادات التذكير على هذا الجهاز فقط.")
            }
            Section("نص القرآن الكريم") {
                Text("نص القرآن الكريم من مشروع تنزيل (Tanzil Quran Text, Uthmani, Version 1.1)، منسوخ كما هو دون تعديل.")
                Link("tanzil.net", destination: URL(string: "https://tanzil.net")!)
                Text(Self.tanzilNotice)
                    .font(.caption.monospaced())
                    .environment(\.layoutDirection, .leftToRight)
            }
            Section("حصن المسلم") {
                Text("«حصن المسلم من أذكار الكتاب والسنة» لسعيد بن علي بن وهف القحطاني. النص من مستودع HisnElMuslim (Abdellah SELLAM، رخصة MIT). مراجعة الحقوق قبل النشر لم تكتمل بعد.")
                Text(Self.mitNotice)
                    .font(.caption.monospaced())
                    .environment(\.layoutDirection, .leftToRight)
            }
            Section("الأذكار والأدعية") {
                Text("مختارات أعدّها المشروع. الآيات منها من نص تنزيل، وبقية النصوص بانتظار المراجعة العلمية.")
            }
            Section("خط القرآن") {
                Text("خط Amiri Quran، رخصة SIL Open Font License 1.1.")
                if let url = QuranFont.licenseURL, let text = try? String(contentsOf: url, encoding: .utf8) {
                    DisclosureGroup("نص الرخصة") {
                        Text(text)
                            .font(.caption2.monospaced())
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }
        }
            Section("صفحات المصحف") {
                Text("خط DigitalKhatt New Madina (Amine Anane وTarteel)، رخصة SIL Open Font License 1.1. مواضع الأسطر من مشروع DigitalKhatt (رخصة MIT)، والنص المعروض هو نص تنزيل نفسه.")
                if let url = MushafFont.licenseURL, let text = try? String(contentsOf: url, encoding: .utf8) {
                    DisclosureGroup("رخصة الخط") {
                        Text(text)
                            .font(.caption2.monospaced())
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                if let url = QuranMushafLayout.noticeURL, let text = try? String(contentsOf: url, encoding: .utf8) {
                    DisclosureGroup("رخصة مواضع الأسطر") {
                        Text(text)
                            .font(.caption2.monospaced())
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }
        }
        .navigationTitle("حول التطبيق")
    }

    static let tanzilNotice = """
    Tanzil Quran Text (Uthmani, Version 1.1)
    Copyright (C) 2007-2026 Tanzil Project
    License: Creative Commons Attribution 3.0

    This copy of the Quran text is carefully produced, highly verified and continuously monitored by a group of specialists at Tanzil Project.

    TERMS OF USE:
    - Permission is granted to copy and distribute verbatim copies of this text, but CHANGING IT IS NOT ALLOWED.
    - This Quran text can be used in any website or application, provided that its source (Tanzil Project) is clearly indicated, and a link is made to tanzil.net to enable users to keep track of changes.
    - This copyright notice shall be included in all verbatim copies of the text, and shall be reproduced appropriately in all files derived from or containing substantial portion of this text.

    Please check updates at: http://tanzil.net/updates/
    """

    static let mitNotice = """
    MIT License
    Copyright (c) 2021 Abdellah SELLAM

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
