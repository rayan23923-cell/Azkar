#!/usr/bin/env python3
"""Writes tools/content/hisn.crosscheck.json: how each item of the primary Hisn source
lines up with a second, independent transcription of the book.

Primary source (committed verbatim, MIT):
  Packages/IslamicCore/Upstream/hisn/asellam/hisn.json
Cross-check transcription (fetched by a CI runner, not committed):
  <raw>/shamela/NNN.html, parsed by extract_hisn.py (book numbering 1..267, footnotes)
Official numbering check:
  <raw>/binwahaf_audio_series_897.html, the author's own item list

Nothing in the primary text is changed here. This script only records, per item:
  - the book chapter / book item number it matches (or null when unsure),
  - how much of its letters the matched book item contains,
  - Quran verse references taken from the book's footnotes,
  - repetition phrases the book text states for that item,
  - flags for anything a reviewer must look at.

Run: python3 tools/content/hisn/prepare_crosscheck.py <raw-dir>
"""
import difflib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_hisn as ex  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
PRIMARY = ROOT / "Packages/IslamicCore/Upstream/hisn/asellam/hisn.json"
TANZIL = ROOT / "Packages/IslamicCore/Upstream/tanzil/quran-uthmani.xml"
OUT = ROOT / "tools/content/hisn.crosscheck.json"

L = ex.letters
MATCH_THRESHOLD = 0.85
QURAN_THRESHOLD = 0.85
COVERAGE_THRESHOLD = 0.90

# Repetition phrases as the book writes them, compared on letters only.
REPEAT_PHRASES = [
    ("ثلاثاوثلاثين", 33), ("اربعاوثلاثين", 34),
    ("ثلاثمرات", 3), ("ثلاثا", 3), ("اربعمرات", 4), ("سبعمرات", 7),
    ("عشرمرات", 10), ("مائةمرة", 100), ("مئةمرة", 100), ("مرتين", 2),
]


def contained(part, whole):
    """Share of `part`'s letters that appear, in order, inside `whole`."""
    if not part:
        return 0.0
    blocks = difflib.SequenceMatcher(None, part, whole, autojunk=False).get_matching_blocks()
    return sum(b.size for b in blocks) / len(part)


def repeat_values(text):
    key, found = L(text), set()
    for phrase, value in REPEAT_PHRASES:
        if phrase in key:
            found.add(value)
            key = key.replace(phrase, "")
    return sorted(found)


def tanzil():
    root = ET.parse(TANZIL).getroot()
    surahs = {}
    for sura in root.findall("sura"):
        surahs[int(sura.get("index"))] = (sura.get("name"), [a.get("text") for a in sura.findall("aya")])
    return surahs


def skeleton(text):
    """Letters with alef/hamza seats dropped: bridges Uthmani and common spelling. Comparison only."""
    key = L(re.sub(r"\(\d+\)|[٠-٩0-9]", "", text)).replace("ى", "ي").replace("ة", "ه")
    return re.sub("[اؤئء]", "", key)


def quran_index(surahs):
    index = []
    for sid, (_, ayas) in surahs.items():
        buf, offsets = "", []
        for number, aya in enumerate(ayas, start=1):
            offsets.append((len(buf), len(buf) + len(skeleton(aya)), number))
            buf += skeleton(aya)
        index.append((sid, buf, offsets))
    return index


def locate(segment, index):
    """Exact skeleton match of a quoted passage inside one surah; None if absent or ambiguous."""
    key = skeleton(segment)
    if len(key) < 8:
        return None
    hits = []
    for sid, buf, offsets in index:
        start = buf.find(key)
        while start != -1:
            end = start + len(key)
            first = next(o for o in offsets if o[0] <= start < o[1])
            last = next(o for o in offsets if o[0] < end <= o[1])
            hits.append({"surah": sid, "fromAyah": first[2], "toAyah": last[2],
                         "wholeVerses": start == first[0] and end == last[1], "match": "EXACT"})
            start = buf.find(key, start + 1)
    return hits[0] if len(hits) == 1 else None


def fuzzy_locate(segment, refs, surahs):
    """Book-footnote reference whose verses contain the passage closely enough."""
    for ref in refs:
        verses = surahs[ref["surah"]][1][ref["fromAyah"] - 1:ref["toAyah"]]
        if contained(skeleton(segment), skeleton(" ".join(verses))) >= QURAN_THRESHOLD:
            return dict(ref, wholeVerses=False, match="FUZZY")
    return None


def quran_refs(footnotes, surahs):
    names = {L(name): sid for sid, (name, _) in surahs.items()}
    refs = []
    for note in footnotes:
        text = (note.get("text") or "").translate(ex.AR_DIGITS)
        for m in re.finditer(r"سورة\s+([^،,\d]+?)\s*[،,]\s*(?:الآية|الآيات|الآيتان|الاية|رقم)?\s*:?\s*(\d+)(?:\s*-\s*(\d+))?", text):
            sid = names.get(L(m.group(1)))
            if not sid:
                continue
            a = int(m.group(2))
            b = int(m.group(3)) if m.group(3) else a
            if 1 <= a <= b <= len(surahs[sid][1]):
                refs.append({"surah": sid, "fromAyah": a, "toAyah": b})
    return refs


def main():
    raw = Path(sys.argv[1])
    primary = json.loads(PRIMARY.read_text(encoding="utf-8"))
    ex.OUT = Path("/dev/null")
    book = book_items(raw)
    surahs = tanzil()
    index = quran_index(surahs)
    official = ex.official_numbers(raw)

    titles = list(primary)
    sm = difflib.SequenceMatcher(None, [L(t) for t in titles], [L(c["titleArabic"]) for c in book], autojunk=False)
    chapter_map = {}
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal" or (tag == "replace" and i2 - i1 == j2 - j1):
            for k in range(i2 - i1):
                chapter_map[i1 + k] = j1 + k
        elif tag == "replace" and j2 - j1 == 1:
            for k in range(i1, i2):
                chapter_map[k] = j1   # e.g. morning and evening are one book chapter

    chapters_out = []
    counts = {"matched": 0, "unmatched": 0, "quranResolved": 0, "quranUnresolved": 0,
              "repeatConsistent": 0, "repeatConflict": 0}
    for ci, title in enumerate(titles):
        bj = chapter_map.get(ci)
        bchap = book[bj] if bj is not None else None
        items_out = []
        last_number = 0
        for ii, item in enumerate(primary[title]["Adhkar"]):
            key = L(item["Text"])
            # Book order is kept: an item never matches a book item before the previous match.
            best, score = None, 0.0
            for bitem in (bchap["items"] if bchap else []):
                if bitem["number"] < last_number:
                    continue
                s = contained(key, L(bitem["arabicText"]))
                if s > score + 1e-9:
                    best, score = bitem, s
            flags = []
            if len(key) < 20:
                flags.append("SHORT_TEXT_MATCH")
            if not bchap:
                flags.append("CHAPTER_NOT_MATCHED")
            matched = best is not None and score >= MATCH_THRESHOLD
            if not matched:
                flags.append("ITEM_NOT_MATCHED_IN_BOOK")
            counts["matched" if matched else "unmatched"] += 1
            if matched:
                last_number = best["number"]

            citations, quran = [], "NONE"
            own = re.findall(r"\{(.*?)\}", item["Text"], re.S)
            # Passages the book itself marks as Quran also count when this text carries them,
            # even where the primary source left out the braces.
            from_book = re.findall(r"\{(.*?)\}", best["arabicText"], re.S) if matched else []
            fallback = quran_refs(best["footnotes"], surahs) if matched else []
            item_skeleton = skeleton(item["Text"])
            unresolved = 0
            for seg, required in [(x, True) for x in own] + [(x, False) for x in from_book]:
                hit = locate(seg, index) or fuzzy_locate(seg, fallback, surahs)
                if hit and contained(skeleton(seg), item_skeleton) < QURAN_THRESHOLD:
                    hit = None if not required else hit
                    if hit is None:
                        continue
                if hit is None:
                    if required:
                        unresolved += 1
                        flags.append("QURAN_SEGMENT_UNRESOLVED:" + seg.strip()[:30])
                    continue
                key = (hit["surah"], hit["fromAyah"], hit["toAyah"])
                if key in {(c["surah"], c["fromAyah"], c["toAyah"]) for c in citations}:
                    continue
                if hit["match"] == "FUZZY":
                    flags.append(f"QURAN_FUZZY_MATCH:{key[0]}:{key[1]}-{key[2]}")
                if not required:
                    flags.append(f"QURAN_UNBRACED_IN_SOURCE:{key[0]}:{key[1]}-{key[2]}")
                citations.append(hit)
            citations.sort(key=lambda c: item_skeleton.find(skeleton(" ".join(
                surahs[c["surah"]][1][c["fromAyah"] - 1:c["toAyah"]]))[:12]))
            if own or citations:
                quran = "RESOLVED" if unresolved == 0 else ("PARTIAL" if citations else "UNRESOLVED")
                counts["quranResolved" if quran == "RESOLVED" else "quranUnresolved"] += 1

            book_repeats = repeat_values(best["arabicText"]) if matched else []
            count = item["Count"]
            consistent = (count in book_repeats) or (count == 1 and not book_repeats)
            if matched:
                counts["repeatConsistent" if consistent else "repeatConflict"] += 1
                if not consistent:
                    flags.append(f"REPEAT_CONFLICT:source={count},book={book_repeats}")
            else:
                flags.append("REPEAT_UNVERIFIED")

            items_out.append({
                "index": ii + 1,
                "bookItemNumber": best["number"] if matched else None,
                "bookMatch": round(score, 3),
                "inOfficialItemList": (best["number"] in official) if matched else None,
                "quran": quran,
                "quranCitations": citations,
                "bookRepeatValues": book_repeats,
                "repeatConsistent": consistent if matched else None,
                "flags": flags,
            })
        # Book text that none of this chapter's items carry, e.g. a surah left out.
        if bchap:
            for bitem in bchap["items"]:
                group = [it for it in items_out if it["bookItemNumber"] == bitem["number"]]
                if not group:
                    continue
                joined = "".join(L(primary[title]["Adhkar"][it["index"] - 1]["Text"]) for it in group)
                coverage = contained(L(bitem["arabicText"]), joined)
                if coverage < COVERAGE_THRESHOLD:
                    counts["bookTextNotCovered"] = counts.get("bookTextNotCovered", 0) + 1
                    for it in group:
                        it["flags"].append(f"BOOK_TEXT_NOT_COVERED:{coverage:.2f}")
        chapters_out.append({
            "index": ci + 1,
            "titleArabic": title,
            "bookChapterNumber": bchap["number"] if bchap else None,
            "items": items_out,
        })

    out = {
        "primary": "Packages/IslamicCore/Upstream/hisn/asellam/hisn.json",
        "crossCheck": "https://shamela.ws/book/31307 (151 pages) and https://binwahaf.com/ar/audio-book-series/897/",
        "bookChapters": len(book),
        "bookItems": sum(len(c["items"]) for c in book),
        "counts": counts,
        "chapters": chapters_out,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(counts, ensure_ascii=False))


def book_items(raw):
    """Runs extract_hisn on the raw pages and returns its chapters (not written anywhere)."""
    import io
    import contextlib
    target = ROOT / "tools/content/.hisn.book.tmp.json"
    ex.OUT = target
    sys_argv = sys.argv
    sys.argv = ["extract_hisn.py", str(raw)]
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            ex.main()
        return json.loads(target.read_text(encoding="utf-8"))["chapters"]
    finally:
        sys.argv = sys_argv
        target.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
