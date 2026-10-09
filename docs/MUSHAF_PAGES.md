# Mushaf pages («صفحات المصحف»)

The Quran reader has two modes, chosen in Settings › القراءة › «عرض القرآن», or with the
toolbar button in either reader. The place is kept when switching.

- **آية آية** (default): the original reader, unchanged. It keeps verse actions (copy, share,
  bookmark) and PiP.
- **صفحات المصحف**: the 604 pages of the Madani mushaf, swiped right to left.

## What a page shows

- **Header:** the juz on the right («الجزء السادس عشر»), the surah on the left.
- **Surah start:** a title band, then the basmala (except Al-Fatiha and At-Tawba).
  - The band is drawn in code: a green lattice panel, gold borders, rosettes, and the name in
    a cartouche.
- **Verses:** justified, each ending with the end-of-verse sign and its number in
  Eastern Arabic digits.
- **Footer:** the page number in a gold cartouche.

Pages are cream, or dark in dark mode.

## What is exact and what is not

- **Exact:** which verses are on each page, from the Tanzil page metadata already in the app.
  `QuranMushafPageTests` checks that every verse is on exactly one page, in order, with the
  bundled text unchanged, and checks known pages (1, 305 = Maryam 1–11, 604).
- **Not exact:** the 15 printed lines per page.
  - Line-for-line pages need the King Fahd Complex page fonts or page images, whose licence
    does not allow bundling them here without permission.
  - The text uses the bundled Amiri Quran font at the largest size (14–30 pt) that fits the
    screen.
- **Not copied:** no artwork from other apps or printed mushafs; the ornaments are drawn in
  code.

## Reading position and progress

- Opening saves the verse opened. Turning a page saves its first verse.
- A surah whose last verse is on a page shown counts as read today, as in the verse reader.

## Not in this mode

Per-verse actions and PiP stay in «آية آية». No device test yet (NOT_TESTED).
