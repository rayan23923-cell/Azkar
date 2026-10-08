#!/usr/bin/env python3
"""Parses the Shamela transcription of Hisn Al-Muslim into chapters and numbered items.

Used only as an independent cross-check by prepare_crosscheck.py; it is not the
bundled text. See
docs/phases/PHASE_2C_HISN_IMPLEMENTATION.md for the source strategy.

Inputs (fetched by a CI runner, not committed):
  <raw>/shamela/NNN.html            Shamela book 31307, pages 1..151 (readable transcription)
  <raw>/binwahaf_audio_series_897.html  the author's official item list (numbers + incipits)
  <raw>/fetch.log                   HTTP log incl. SHA-256 of the author's official PDF

The Arabic wording is copied as transcribed. Only these mechanical steps are applied:
  - HTML tags and the site's copy buttons are removed, entities are decoded;
  - runs of whitespace become one space; a paragraph split by a page break is rejoined;
  - page-local footnote markers such as "(٢)" are lifted out of the text into
    references (the footnote text itself is kept verbatim);
  - the leading "N - (M)" item numbering is lifted into number / chapter order fields.
Nothing is normalized, corrected or re-spelled.

Run: python3 tools/content/hisn/extract_hisn.py <raw-dir>
"""
import hashlib
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "tools/content/.hisn.book.tmp.json"

AR_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
FN = "\u0000FN{}\u0000"
FN_RE = re.compile(r"\s*\u0000FN(\d+)\u0000")
NUM_RE = re.compile(r"^([٠-٩]+)\s*-\s*(.*)$", re.S)


def to_int(arabic_digits):
    return int(arabic_digits.translate(AR_DIGITS))


def letters(text):
    """Comparison key only: Arabic letters without marks. Never stored as display text."""
    text = re.sub(r"[ً-ٰٟۖ-ۭـ]", "", text)
    text = text.replace("ٱ", "ا").replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    return re.sub(r"[^ء-ي]", "", text)


def clean(fragment):
    fragment = re.sub(r'<a href="#p\d+" class="btn_tag[^"]*">.*?</a>', "", fragment, flags=re.S)
    fragment = re.sub(r'<span class="c2">\(([٠-٩]+)\)</span>', lambda m: FN.format(to_int(m.group(1))), fragment)
    fragment = re.sub(r"<[^>]+>", "", fragment)
    fragment = html.unescape(fragment)
    return re.sub(r"\s+", " ", fragment).strip()


def read_page(path):
    s = path.read_text(encoding="utf-8")
    m = re.search(r'<div class="nass[^"]*" data-page-id="(\d+)" data-page-num="(\d+)"[^>]*>(.*?)<div id="appended_pages">', s, re.S)
    body = m.group(3)
    hamesh = ""
    hm = re.search(r'<p class="hamesh">(.*?)</p>', body, re.S)
    if hm:
        hamesh = hm.group(1)
        body = body[: hm.start()]
    paras = [clean(p) for p in re.findall(r"<p>(.*?)</p>", body, re.S)]
    notes = [html.unescape(re.sub(r"<[^>]+>", "", line)).strip() for line in re.split(r"<br\s*/?>", hamesh)]
    toc = [(to_int(n), html.unescape(t).strip(), int(pg)) for pg, n, t in
           re.findall(r'href="https://shamela.ws/book/31307/(\d+)">([٠-٩]+) - ([^<]+)</a>', s)]
    return int(m.group(2)), [p for p in paras if p], [n for n in notes if n], toc, hashlib.sha256(s.encode()).hexdigest()


def official_numbers(raw):
    s = (raw / "binwahaf_audio_series_897.html").read_text(encoding="utf-8")
    seen, numbers = set(), set()
    for url, title in re.findall(r'href="(https://binwahaf.com/ar/audio-book-lesson/\d+/)"[^>]*>(.*?)</a>', s, re.S):
        title = html.unescape(re.sub("<[^>]+>", "", title)).strip()
        m = re.match(r"^(\d+)(?:\s*[-–]\s*(\d+))?\s*-", title)
        if not m or (url, title) in seen:
            continue
        seen.add((url, title))
        a = int(m.group(1))
        b = int(m.group(2)) if m.group(2) else a
        numbers.update(range(a, b + 1))
    return numbers


def main():
    raw = Path(sys.argv[1])
    pages = sorted((raw / "shamela").glob("*.html"))
    book = {"frontMatter": [], "closing": [], "chapters": []}
    footnotes = {}           # (page, n) -> text
    toc = None
    page_hashes = {}
    last_note_key = None
    unit = book["frontMatter"]   # list of {"text", "notes": [(page, n)]} paragraphs being filled
    current_item = None
    next_chapter, next_item = 1, 1
    for path in pages:
        page_num, paras, notes, page_toc, digest = read_page(path)
        page_hashes[path.name] = digest
        if toc is None and page_toc:
            toc = {n: (t, pg) for n, t, pg in page_toc}
        for line in notes:
            m = re.match(r"^\(([٠-٩]+)\)\s*(.*)$", line, re.S)
            if m:
                last_note_key = (page_num, to_int(m.group(1)))
                footnotes[last_note_key] = m.group(2).strip()
            elif last_note_key:
                footnotes[last_note_key] += " " + line   # continuation from the previous page
        for position, para in enumerate(paras):
            m = NUM_RE.match(para)
            number = to_int(m.group(1)) if m else None
            rest = m.group(2) if m else None
            if (m and number == next_chapter and next_chapter in toc and FN_RE.search(rest) is None
                    and letters(rest) == letters(toc[next_chapter][0])):
                chapter = {"number": number, "titleArabic": rest, "introduction": [], "items": [],
                           "sourcePage": page_num}
                book["chapters"].append(chapter)
                unit, current_item = chapter["introduction"], None
                next_chapter += 1
                continue
            if m and number == next_item and book["chapters"]:
                chapter = book["chapters"][-1]
                local = None
                lm = re.match(r"^\u0000FN(\d+)\u0000\s*(.*)$", rest, re.S)
                if lm and int(lm.group(1)) == len(chapter["items"]) + 1:
                    local, rest = int(lm.group(1)), lm.group(2)
                current_item = {"number": number, "chapterLocalNumber": local, "paragraphs": [],
                                "sourcePage": page_num}
                chapter["items"].append(current_item)
                unit = current_item["paragraphs"]
                next_item += 1
                para = rest
            elif (next_item > 1 and not m and next_chapter > max(toc) and
                  letters(para).startswith(letters("وصلى الله وسلم وبارك على نبينا محمد"))):
                unit = book["closing"]
            keys = [(page_num, int(n)) for n in FN_RE.findall(para)]
            # A page that opens mid-paragraph continues the previous page's paragraph.
            joins = position == 0 and not m and bool(unit)
            unit.append({"text": FN_RE.sub("", para).strip(), "notes": keys, "join": joins})

    assert toc and next_chapter - 1 == max(toc), f"chapters parsed {next_chapter - 1} vs toc {max(toc)}"
    official = official_numbers(raw)

    def resolve(paragraphs):
        refs = []
        for p in paragraphs:
            for key in p["notes"]:
                refs.append({"page": key[0], "marker": key[1], "text": footnotes.get(key)})
        return refs

    def text_of(paragraphs):
        out = ""
        for p in paragraphs:
            if p["text"]:
                out += (" " if p.get("join") else "\n") + p["text"] if out else p["text"]
        return out

    chapters = []
    for ch in book["chapters"]:
        items = []
        for it in ch["items"]:
            items.append({
                "number": it["number"],
                "chapterLocalNumber": it["chapterLocalNumber"],
                "arabicText": text_of(it["paragraphs"]),
                "footnotes": resolve(it["paragraphs"]),
                "sourcePage": it["sourcePage"],
                "inOfficialItemList": it["number"] in official,
            })
        chapters.append({
            "number": ch["number"],
            "titleArabic": ch["titleArabic"],
            "tocTitle": toc[ch["number"]][0],
            "introduction": text_of(ch["introduction"]),
            "introductionFootnotes": resolve(ch["introduction"]),
            "sourcePage": ch["sourcePage"],
            "items": items,
        })
    out = {
        "contentVersion": 1,
        "extraction": {
            "method": "Shamela HTML transcription, mechanically cleaned by tools/content/hisn/extract_hisn.py",
            "transcriptionURL": "https://shamela.ws/book/31307",
            "transcriptionPages": len(pages),
            "transcriptionPageSHA256": page_hashes,
            "officialItemNumbersFound": len(official),
        },
        "frontMatter": {"text": text_of(book["frontMatter"]), "footnotes": resolve(book["frontMatter"])},
        "closing": {"text": text_of(book["closing"]), "footnotes": resolve(book["closing"])},
        "chapters": chapters,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    n_items = sum(len(c["items"]) for c in chapters)
    missing_notes = sum(1 for c in chapters for i in c["items"] for f in i["footnotes"] if f["text"] is None)
    print(f"chapters {len(chapters)} items {n_items} missing footnotes {missing_notes} "
          f"official numbers {len(official)}")


if __name__ == "__main__":
    main()
