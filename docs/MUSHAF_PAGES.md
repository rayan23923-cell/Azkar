# Mushaf pages («صفحات المصحف»)

The Quran reader has two modes, chosen in Settings › القراءة › «عرض القرآن», or with the
toolbar button in either reader. The place is kept when switching.

- **آية آية** (default): the original reader, unchanged. It keeps verse actions (copy, share,
  bookmark) and PiP.
- **صفحات المصحف**: the 604 pages of the Madani mushaf, swiped right to left.

Mushaf pages have two styles, in Settings › القراءة › «شكل صفحات المصحف»:

- **مطابق للمطبوع (١٥ سطراً)** (default): line for line as the Madina mushaf (King Fahd
  Complex, 1421H print). Each page has 15 rows (8 on pages 1 and 2), each row a title band,
  the basmala, or exactly the words of the printed line, in the DigitalKhatt New Madina font
  (OFL). Words are spread to fill the row; a row too long for the screen at the page's size is
  narrowed horizontally rather than wrapped.
- **مرن (خط أميري)**: the earlier style: the page's verses flowed in Amiri Quran at the
  largest size that fits.

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
- **Exact in the printed style:** which words are on each of the 15 lines.
  - The line positions come from the DigitalKhatt project (MIT), whose Madina page text follows
    the 1421H print; `tools/mushaf/make_madina_lines.py` keeps only where each line starts and
    stops if any verse's words or end sign do not line up with the bundled text.
  - The words drawn are cut from the bundled Tanzil text. `QuranMushafLinesTests` joins them
    back and checks every verse is its text character for character, every page has the
    verses of the page metadata, and 114 titles and 112 basmalas.
  - Only for drawing, two marks the font spells differently are handed to it as the
    equivalent code points: U+06EA as U+065C (the imala dot of 11:41) and U+06EB as U+06EC (the
    ishmam of 12:11). The stored text is unchanged.
- **Page breaks:** the printed style follows the 1421H print's page breaks, its page numbers
  and juz shown accordingly. On 25 pages (121–123, 145, 532–534, 565, 568, 570, 576, 584, 586,
  588–590, 592–600) they fall a few verses away from the Tanzil page metadata, which the
  flowing style and the rest of the app keep. Switching style keeps the verse in view.
- **Not exact:** the shapes of the print. The King Fahd Complex fonts are the Complex's
  property and may not be reproduced without its written approval, so they are not bundled.
  DigitalKhatt New Madina is an independent font in the same script; the print also stretches
  letters to fill a line, which this screen does with the spaces between words instead.
- **Not copied:** no glyphs, images or artwork from other apps or printed mushafs; the ornaments are drawn in
  code.

## Reading position and progress

- Opening saves the verse opened. Turning a page saves its first verse.
- A surah whose last verse is on a page shown counts as read today, as in the verse reader.

## Not in this mode

Per-verse actions and PiP stay in «آية آية». No device test yet (NOT_TESTED).
