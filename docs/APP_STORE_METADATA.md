# App Store metadata (draft)

**Draft only. Nothing was entered in App Store Connect.** Everything below is a proposal for
the owner to edit. The URLs must be real ones the owner controls.

## Identity

| Field | Draft |
|---|---|
| App name (30) | أذكار |
| Alternative names if «أذكار» is taken | أذكار: القرآن وحصن المسلم · أذكار المسلم |
| Subtitle (30) | القرآن وحصن المسلم والأذكار |
| Primary category | Reference |
| Secondary category | Lifestyle |
| Primary language | Arabic |
| Price | Free (no in-app purchases) |

## Promotional text (170)

> القرآن الكريم وحصن المسلم وأذكار الصباح والمساء في تطبيق واحد، يعمل دون إنترنت، بلا
> إعلانات ولا جمع بيانات.

## Description

> «أذكار» يجمع لك:
>
> • القرآن الكريم كاملاً بالرسم العثماني من مشروع تنزيل، بخط واضح، مع فهرس السور والأجزاء،
>   والبحث في الآيات، والعلامات، ومتابعة القراءة من حيث توقفت.
>
> • حصن المسلم مقسَّماً إلى أبوابه، مع عدّاد للتكرار، ومتابعة القراءة، والبحث في الأبواب
>   والأذكار.
>
> • أذكار الصباح والمساء وبعد الصلاة والنوم، وأدعية من القرآن والسنة، مع عدّاد يحفظ موضعك.
>
> • بحث واحد في كل المحتوى.
>
> • نسخ النص ومشاركته، أو مشاركته صورةً جميلة.
>
> • المفضلة، وتذكير يومي بأذكار الصباح والمساء في الوقت الذي تختاره.
>
> • الوضع الداكن، وتكبير الخط، ودعم VoiceOver.
>
> يعمل التطبيق كله دون اتصال بالإنترنت. لا يجمع أي بيانات، ولا يحتوي على إعلانات.
>
> نص القرآن الكريم من مشروع تنزيل (tanzil.net).

The last line is required by the Tanzil terms. The Hisn attribution wording waits on the rights
decision.

## Keywords (100 characters, comma-separated)

`قرآن,مصحف,حصن المسلم,أذكار,الصباح,المساء,دعاء,أدعية,تسبيح,عداد,ذكر,سورة,آية,إسلام`

Check the length in App Store Connect.

## URLs (EXTERNAL_BLOCKER)

| Field | Status |
|---|---|
| Privacy Policy URL | **Required. None exists.** The in-app privacy statement («حول التطبيق») can be the basis. |
| Support URL | **Required. None exists.** |
| Marketing URL | Optional |

## App Privacy («nutrition label»)

- Data collection: **Data Not Collected**. There is no network code, no analytics, no
  accounts, and the privacy manifest declares no collected data.
- Tracking: **No**.

## Age rating

There is no objectionable content, user-generated content, web access or purchases. Expected
rating: 4+. Answer «None» throughout the questionnaire.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is in the build, so App Store Connect will not ask.

## Review notes (draft)

> The app is entirely offline. It contains the Quran (Tanzil Uthmani text), the book Hisn
> Al-Muslim, and a selection of adhkar and duas. No sign-in is needed. The only permission is
> notifications, requested when the user turns on a daily reminder in Settings (الإعدادات).
> The app does not play audio in this version.

## Screenshots

The capture list is in [Screenshot checklist](#screenshot-checklist) below.

## Screenshot checklist

The sizes App Store Connect asks for:

- iPhone 6.9″: 1320 × 2868, or 6.7″ 1290 × 2796;
- iPad 13″: 2064 × 2752, because the app supports iPad (or make the app iPhone-only).

Capture from a Release build in Arabic, in light mode, with one set in dark mode if wanted.

| # | Screen | What to show |
|---|---|---|
| 1 | Home | Today's adhkar with one completed mark, «متابعة», search entry |
| 2 | Quran index | Surah list with «متابعة القراءة» at the top |
| 3 | Quran reading | Al-Fatiha or the opening of Al-Baqarah, with the basmala, ayah markers and the position bar |
| 4 | Hisn | The index of أبواب, or a reader with the counter |
| 5 | Dhikr / dua | The morning adhkar reader with the large counter |
| 6 | Search | Results for «الرحمن» across sources, with highlights |
| 7 | Settings | Reminders on with a time, appearance, text sizes |
| 8 (optional) | Share image | A verse card in the Quran font |

No real screenshots were produced; there was no simulator or device capture in this
environment.
