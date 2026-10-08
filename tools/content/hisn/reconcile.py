#!/usr/bin/env python3
"""Writes tools/content/hisn.reconciliation.json: an item-by-item reconciliation of the
bundled Hisn source (asellam/HisnElMuslim) against the book's own structure
(Shamela 31307 transcription, 132 chapters / 267 numbered items) and the author's
official item list (binwahaf audio series 897).

Phase 2C (prepare_crosscheck.py) matched items monotonically and only forward
(how much of the source text is inside a book item). That hid swapped items,
items with added words and splits. This script:
  - scores every source item against every book item of its chapter, in both
    directions (source-in-book and book-in-source);
  - allows order differences and records them instead of skipping the item;
  - groups source items per book number to show splits, and book numbers per
    source item to show merges;
  - looks for unmatched source text in chapter introductions and footnotes;
  - lists repetition conflicts, Quran citations and reference differences.

Nothing in the bundled content is changed. No match here is used by the app.
Run: python3 tools/content/hisn/reconcile.py <raw-dir>
"""
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_hisn as ex  # noqa: E402
import prepare_crosscheck as pc  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
PRIMARY = ROOT / "Packages/IslamicCore/Upstream/hisn/asellam/hisn.json"
CROSSCHECK = ROOT / "tools/content/hisn.crosscheck.json"
BUNDLED = ROOT / "Packages/IslamicCore/Sources/IslamicCore/Resources/Content/hisn.json"
OUT = ROOT / "tools/content/hisn.reconciliation.json"

L = ex.letters
contained = pc.contained

SHORT = 20           # letters; below this, only exact substrings count as a match
MATCH_FWD = 0.85     # source letters inside the book item
MATCH_REV = 0.90     # book letters inside the source item (source carries additions)
MATCH_REV_MIN_FWD = 0.60
STRONG = 0.95
MERGE_REV = 0.90
ARABIC_DIGITS = ex.AR_DIGITS


def book_core(text):
    """The dhikr wording itself: the book puts it in ((...)) and its instructions in (...)."""
    parts = re.findall(r"\(\((.*?)\)\)", text, re.S)
    return " ".join(parts) if parts else text


def score(src_key, book_text):
    """(source letters inside the whole book item, the book's dhikr wording inside the source)."""
    book_key = L(book_text)
    if len(src_key) < SHORT:
        fwd = 1.0 if src_key and src_key in book_key else contained(src_key, book_key)
    else:
        fwd = contained(src_key, book_key)
    return fwd, contained(L(book_core(book_text)), src_key)


def refkey(text):
    """Reference comparison key: letters and digits (volume/page numbers matter here)."""
    text = re.sub(r"[\u064B-\u065F\u0670\u0640]", "", (text or "").translate(ARABIC_DIGITS))
    return re.sub(r"[^\u0621-\u064A0-9]", "", text)


def ref_similarity(source_reference, footnotes):
    key = refkey(source_reference)
    notes = refkey(" ".join(footnote_text(n) for n in footnotes))
    return contained(key, notes) if key and notes else 0.0


def official_numbers(raw):
    """The author's audio list, including combined entries written "135:133-" or "115،114-"."""
    s = (raw / "binwahaf_audio_series_897.html").read_text(encoding="utf-8")
    seen, numbers = set(), set()
    for url, title in re.findall(r'href="(https://binwahaf.com/ar/audio-book-lesson/\d+/)"[^>]*>(.*?)</a>', s, re.S):
        title = html.unescape(re.sub("<[^>]+>", "", title)).strip()
        m = re.match(r"^(\d+)(?:\s*[-–:،,]\s*(\d+))?\s*-", title)
        if not m or (url, title) in seen:
            continue
        seen.add((url, title))
        a, b = sorted((int(m.group(1)), int(m.group(2) or m.group(1))))
        numbers.update(range(a, b + 1))
    return numbers


def raw_footnotes(raw):
    """Every footnote line of every transcription page, independent of item assignment."""
    notes = []
    for path in sorted((raw / "shamela").glob("*.html")):
        page, _, lines, _, _ = ex.read_page(path)
        notes.extend({"page": page, "text": line} for line in lines)
    return notes


def is_match(fwd, rev, short=False, refsim=0.0):
    if short and fwd < 1.0:
        # A short text that is not a literal part of the book item counts only when
        # most of it is there and the reference is the same (e.g. شك / وسوس).
        return fwd >= 0.75 and refsim >= 0.90
    return fwd >= MATCH_FWD or (rev >= MATCH_REV and fwd >= MATCH_REV_MIN_FWD)


def footnote_text(note):
    return (note.get("text") or "").strip()


def find_elsewhere(src_key, book, chapter_number, notes):
    """Where unmatched source text appears in the book outside numbered item text."""
    hits = []
    for chap in book:
        if chapter_number is not None and abs(chap["number"] - chapter_number) > 1:
            continue
        intro = L(chap.get("introduction") or "")
        if intro and contained(src_key, intro) >= MATCH_FWD and len(src_key) >= 8:
            hits.append({"where": "CHAPTER_INTRODUCTION", "bookChapterNumber": chap["number"],
                         "similarity": round(contained(src_key, intro), 3)})
    if len(src_key) >= 8:
        for note in notes:
            key = L(note["text"])
            s = contained(src_key, key) if key else 0.0
            if s >= MATCH_FWD:
                hits.append({"where": "FOOTNOTE", "page": note["page"],
                             "similarity": round(s, 3), "footnote": note["text"]})
    return hits


# ---------------------------------------------------------------- word differences

def word_diff(book_text, source_text, limit=12):
    """Word-level differences on letters only (marks ignored); book wording first."""
    bw = [L(w) for w in book_text.split() if L(w)]
    sw = [L(w) for w in source_text.split() if L(w)]
    sm = pc.difflib.SequenceMatcher(None, bw, sw, autojunk=False)
    out = []
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op != "equal":
            out.append({"op": op, "book": " ".join(bw[i1:i2]), "source": " ".join(sw[j1:j2])})
    return out[:limit]


# Words of narration and instructions around a dhikr («يبدأ برجله اليسرى», «رضي الله عنهما»,
# «ثلاث مرات»): their absence changes no recited wording.
INSTRUCTION_WORDS = {"يبدا", "برجله", "اليسرى", "اليمنى", "يقول", "ذلك", "عقب", "بعد", "كل", "صلاة", "صلاه",
                     "تشهد", "المؤذن", "ثلاث", "ثلاثا", "مرات", "رضي", "الله", "عنهما", "عنه", "النبي"}


# ---------------------------------------------------------------- repetition

COUNT_WORDS = ("ثلاث", "اربع", "سبع", "عشر", "مائه", "مايه", "مئه", "مرتين", "مرار", "مرات", "مره")


def count_phrases(text):
    """The exact wording, as written, of every phrase that states a number of times."""
    words = text.split()
    found, k = [], 0
    while k < len(words):
        key = L(words[k]).replace("ة", "ه").replace("ء", "")
        bare = key[1:] if key.startswith(("و", "ف")) and len(key) > 3 else key
        if bare.startswith(COUNT_WORDS) and not bare.startswith(("عشره", "اربعه")):
            phrase = [words[k]]
            j = k + 1
            while j < len(words) and len(phrase) < 4:
                nxt = L(words[j]).replace("ة", "ه")
                if not nxt or not (nxt.startswith(("مر", "وثلاث", "واحد", "ثلاث")) or nxt in ("في", "اليوم")):
                    break
                phrase.append(words[j])
                j += 1
            found.append(" ".join(phrase).strip("()[]،,.:-"))
            k = j
        else:
            k += 1
    return found


# Decisions for the 13 Phase 2C repetition conflicts. Each one is reasoned from the
# book wording shown in the row (bookCountPhrases) and the source item; nothing here
# changes the bundled count, which stays nil until a reviewer accepts the decision.
REPEAT_DECISIONS = {
    "hisn-016-05": ("PHRASE_LEVEL", None, "HIGH",
                    "The book's ثلاثاً follows the takbir/tahmid/tasbih block only; the isti'adha after it is said once. No single count fits the whole item."),
    "hisn-025-01": ("PHRASE_LEVEL", None, "HIGH",
                    "(ثلاثاً) applies to أستغفر الله only; the du'a after it is said once. The source keeps the instruction inline."),
    "hisn-025-02": ("PHRASE_LEVEL_AND_SOURCE_OMISSION", None, "HIGH",
                    "The book has [ثلاثاً] (an addition from al-Bukhari, per its footnote) after the tahlil only. The source text leaves the bracketed addition out entirely."),
    "hisn-025-04": ("PHRASE_LEVEL", None, "HIGH",
                    "33 applies to each of the three tasbih phrases; the closing tahlil is said once (the source says (مرة واحدة)). No single count fits the whole item."),
    "hisn-027-20": ("RESOLVED_BY_REMATCH", 100, "HIGH",
                    "Phase 2C matched this item to book 92 (ten times). It is book 93: same wording, «مائة مرة إذا أصبح», same Bukhari/Muslim footnote. Source count 100 agrees."),
    "hisn-029-06": ("UNVERIFIED_SOURCE_COUNT", None, "LOW",
                    "Source says 3. The book text (item 104) states no count and its footnote quotes only the hadith opening. Not verifiable from the cross-check; needs the printed edition or the hadith source."),
    "hisn-032-03": ("RESOLVED_BY_SPLIT", 1, "HIGH",
                    "Book 114 is split into four source items. (ثلاثاً) and (ثلاث مرات) belong to the first two parts; «لا يحدث بها أحداً» carries no count."),
    "hisn-032-04": ("RESOLVED_BY_SPLIT", 1, "HIGH",
                    "Part four of book 114 (turning to the other side) carries no count; the book's counts belong to parts one and two."),
    "hisn-119-01": ("NARRATIVE", None, "MEDIUM",
                    "A narration of the Prophet's practice at Safa: the tahlil is said three times with du'a between. The item as a whole is not recited a fixed number of times."),
    "hisn-125-01": ("PHRASE_LEVEL", None, "HIGH",
                    "بسم الله three times and the ta'awwudh seven times, both stated inline. No single count fits the whole item."),
    "hisn-130-02": ("COUNT_INSIDE_HADITH", 1, "MEDIUM",
                    "«مائة مرة» is part of the hadith's wording (what the Prophet did), not an instruction to repeat this item. Source count 1 matches the book layout."),
    "hisn-130-06": ("COUNT_INSIDE_HADITH", 1, "MEDIUM",
                    "As hisn-130-02: «مائة مرة» is inside the hadith text."),
    "hisn-131-02": ("COUNT_INSIDE_HADITH", None, "MEDIUM",
                    "«عشر مرار» is inside the hadith text. Source count 10 treats it as an instruction for the embedded tahlil, while the neighbouring hadith items use 1. Keep nil until a reviewer decides."),
}


# ---------------------------------------------------------------- Quran

def ortho(text):
    """Skeleton that also bridges ىٰ/ا and Uthmani ٱلَّيْل / common اللَّيْل. Comparison only."""
    text = re.sub(r"ىـ?ٰ(?=[\u0621-\u064A])", "ا", text)   # مأوىٰهم / مأواهم, but علىٰ stays على
    return pc.skeleton(text).replace("لليل", "ليل")


def ortho_index(surahs):
    index = []
    for sid, (_, ayas) in surahs.items():
        buf, offsets = "", []
        for number, aya in enumerate(ayas, start=1):
            key = ortho(aya)
            offsets.append((len(buf), len(buf) + len(key), number))
            buf += key
        index.append((sid, buf, offsets))
    return index


def ortho_locate(segment, index):
    key = ortho(segment)
    if len(key) < 6:
        return None, 0
    hits = []
    for sid, buf, offsets in index:
        start = buf.find(key)
        while start != -1:
            end = start + len(key)
            first = next(o for o in offsets if o[0] <= start < o[1])
            last = next(o for o in offsets if o[0] < end <= o[1])
            hits.append({"surah": sid, "fromAyah": first[2], "toAyah": last[2],
                         "coversWholeVerses": start == first[0] and end == last[1]})
            start = buf.find(key, start + 1)
    return (hits[0] if len(hits) == 1 else None), len(hits)


# ---------------------------------------------------------------- references

GRADING = ("صححه", "وصححه", "حسنه", "وحسنه", "حسن لغيره", "إسناده", "اسناده", "ضعيف", "حديث حسن", "حديث صحيح")
COLLECTIONS = ["البخاري", "مسلم", "أبو داود", "الترمذي", "النسائي", "ابن ماجه", "أحمد",
               "الحاكم", "ابن حبان", "ابن السني", "الطبراني", "البيهقي", "مالك", "الدارمي",
               "ابن خزيمة", "البزار", "عبد الرزاق", "ابن أبي شيبة", "أبو يعلى", "البغوي"]


def bare(text):
    text = re.sub("[\u064B-\u065F\u0670\u0640]", "", (text or "").translate(ARABIC_DIGITS))
    return text.replace("ة", "ه").replace("إ", "ا").replace("أ", "ا")


SUNAN = {"أبو داود", "الترمذي", "النسائي", "ابن ماجه"}


def reference_facts(text):
    t = bare(text)
    collections = {c for c in COLLECTIONS if bare(c) in t}
    # «أهل السنن» / «أصحاب السنن» / «الأربعة» name the four Sunan as a group, «إلا النسائي» excludes one.
    if re.search("(اهل|اصحاب) السنن|الاربعه", t):
        group = set(SUNAN)
        for name in SUNAN:
            if re.search("الا " + bare(name), t):
                group.discard(name)
        collections |= group
    return {
        "collections": sorted(collections),
        "volumePages": sorted(set(re.sub(r"\s", "", m) for m in re.findall(r"\d+\s*/\s*\d+", t))),
        "hadithNumbers": sorted(set(re.findall(r"(?:برقم|رقم)[،,:\s]*(\d+)", t))),
        "gradings": sorted({g for g in GRADING if bare(g) in t}),
    }


def book_and_front(raw):
    """Chapters and front matter from extract_hisn, written to a temp file and removed."""
    import contextlib
    import io
    target = ROOT / "tools/content/.hisn.book.tmp.json"
    ex.OUT = target
    argv = sys.argv
    sys.argv = ["extract_hisn.py", str(raw)]
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            ex.main()
        data = json.loads(target.read_text(encoding="utf-8"))
        return data["chapters"], data.get("frontMatter") or {}
    finally:
        sys.argv = argv
        target.unlink(missing_ok=True)


def main():
    raw = Path(sys.argv[1])
    primary = json.loads(PRIMARY.read_text(encoding="utf-8"))
    cross = json.loads(CROSSCHECK.read_text(encoding="utf-8"))
    bundled = json.loads(BUNDLED.read_text(encoding="utf-8"))
    book, front = book_and_front(raw)
    official = official_numbers(raw)
    notes = raw_footnotes(raw)
    book_by_number = {i["number"]: (c, i) for c in book for i in c["items"]}
    bundled_items = {(ci + 1, ii + 1): it for ci, ch in enumerate(bundled["chapters"]) for ii, it in enumerate(ch["items"])}
    titles = list(primary)
    bundled_by_id = {it["id"]: it for ch in bundled["chapters"] for it in ch["items"]}
    surahs = pc.tanzil()
    qindex = ortho_index(surahs)
    pc_index = pc.quran_index(surahs)

    rows = []
    for ci, title in enumerate(titles):
        cc_chapter = cross["chapters"][ci]
        bchap_no = cc_chapter["bookChapterNumber"]
        bchap = book[bchap_no - 1] if bchap_no else None
        chapter_rows = []
        for ii, item in enumerate(primary[title]["Adhkar"]):
            key = L(item["Text"])
            cands = []
            for bitem in (bchap["items"] if bchap else []):
                fwd, rev = score(key, bitem["arabicText"])
                refsim = ref_similarity(item["Reference"], bitem["footnotes"])
                # Text decides; the reference only separates candidates whose text scores
                # tie (e.g. one phrase said 10 times vs 100 times, or a short tasbih).
                cands.append((is_match(fwd, rev, len(key) < SHORT, refsim), round(fwd + rev, 1), refsim, fwd + rev, fwd, rev, bitem))
            cands.sort(key=lambda c: c[:4], reverse=True)
            cands = [(c[0], c[3], c[4], c[5], c[6], c[2]) for c in cands]
            best = cands[0] if cands else None
            matched = bool(best and best[0])
            merged_into = []
            if bchap and not (best and best[2] >= MERGE_REV):
                # Merged only when no single book item holds this text but several are inside it.
                for bitem in bchap["items"]:
                    bkey = L(bitem["arabicText"])
                    if len(bkey) >= 8 and contained(bkey, key) >= MERGE_REV:
                        merged_into.append(bitem["number"])
            bundled_item = bundled_items[(ci + 1, ii + 1)]
            row = {
                "sourceItemId": bundled_item["id"],
                "sourceChapter": ci + 1,
                "sourceChapterTitle": title,
                "bookChapterNumber": bchap_no,
                "sourceOrder": ii + 1,
                "sourceText": item["Text"],
                "sourceCount": item["Count"],
                "sourceReference": item["Reference"],
                "sourceBookNumber": cc_chapter["items"][ii]["bookItemNumber"],
                "matchedBookNumber": best[4]["number"] if matched else None,
                "similarity": round(2 * best[2] * best[3] / (best[2] + best[3]), 3) if best and best[2] + best[3] else 0.0,
                "sourceInBook": round(best[2], 3) if best else 0.0,
                "bookInSource": round(best[3], 3) if best else 0.0,
                "referenceSimilarity": round(best[5], 3) if best else 0.0,
                "exactLetters": bool(matched and L(best[4]["arabicText"]) == key),
                "exactSkeleton": bool(matched and pc.skeleton(best[4]["arabicText"]) == pc.skeleton(item["Text"])),
                "shortText": len(key) < SHORT,
                "mergedBookNumbers": merged_into if len(merged_into) >= 2 else [],
                "_best": best,
            }
            chapter_rows.append(row)

        # Order: an item takes part in an inversion if an earlier item has a larger
        # book number or a later one a smaller number (both sides are flagged).
        numbers = [r["matchedBookNumber"] for r in chapter_rows]
        for k, r in enumerate(chapter_rows):
            n = r["matchedBookNumber"]
            r["orderDifference"] = n is not None and (
                any(m is not None and m > n for m in numbers[:k]) or
                any(m is not None and m < n for m in numbers[k + 1:]))
        # Splits: two or more items of the same source chapter on one book number.
        for r in chapter_rows:
            n = r["matchedBookNumber"]
            r["splitOf"] = n if n is not None and sum(1 for m in numbers if m == n) >= 2 else None
        rows.extend(chapter_rows)

    # Morning and evening are two source chapters on one book chapter.
    pair_chapters = {}
    for r in rows:
        pair_chapters.setdefault(r["bookChapterNumber"], set()).add(r["sourceChapter"])

    for r in rows:
        best = r.pop("_best")
        others = sorted(pair_chapters.get(r["bookChapterNumber"], {r["sourceChapter"]}) - {r["sourceChapter"]})
        r["sharesBookChapterWith"] = others
        if r["matchedBookNumber"] is None:
            r["foundOutsideNumberedText"] = find_elsewhere(L(r["sourceText"]), book, r["bookChapterNumber"], notes)
        qualities = []
        if r["matchedBookNumber"] is None:
            mt = "UNMATCHED"
        else:
            if r["exactLetters"] or r["exactSkeleton"]:
                qualities.append("EXACT")
            elif r["sourceInBook"] >= STRONG and r["bookInSource"] >= STRONG:
                qualities.append("STRONG")
            else:
                qualities.append("WORDING_DIFFERENCE")
            if r["shortText"]:
                qualities.append("SHORT_TEXT")
            if r["splitOf"] is not None:
                qualities.append("SPLIT")
            if r["mergedBookNumbers"]:
                qualities.append("MERGED")
            if r["orderDifference"]:
                qualities.append("ORDER_DIFFERENCE")
            # The primary type is the structural finding when there is one.
            for t in ("ORDER_DIFFERENCE", "SPLIT", "MERGED", "SHORT_TEXT"):
                if t in qualities:
                    mt = t
                    break
            else:
                mt = qualities[0]
        r["matchType"] = mt
        r["matchQualities"] = qualities
        n = r["matchedBookNumber"]
        bitem = book_by_number[n][1] if n else None
        r["wordDifferences"] = word_diff(book_core(bitem["arabicText"]), r["sourceText"]) if bitem and "EXACT" not in qualities else []

        # Bracketed additions «[...]» the book marks as coming from another narration.
        if bitem and r["splitOf"] is None:
            src_letters = L(r["sourceText"])
            r["bookBracketedAdditions"] = [
                {"text": seg.strip(), "inSource": L(seg) in src_letters or contained(L(seg), src_letters) >= 0.95}
                for seg in re.findall(r"\[([^\]]+)\]", bitem["arabicText"]) if len(L(seg)) >= 4]
        # Word differences inside the recited wording, as opposed to narration or instructions.
        r["dhikrWordingDifferences"] = [
            o for o in r["wordDifferences"]
            if o["op"] in ("delete", "replace") and len(o["book"].replace(" ", "")) >= 4
            and o["book"].replace(" ", "") != o["source"].replace(" ", "")
            and not set(o["book"].split()) <= INSTRUCTION_WORDS
            and not (o["op"] == "replace" and ortho(o["book"]) == ortho(o["source"]))]

        # Evening wording the book gives in a footnote («وإذا أمسى قال: ...»).
        if r["sharesBookChapterWith"] and "EXACT" not in qualities:
            src_key = L(r["sourceText"])
            best_note = None
            for note in notes:
                if "أمسى" not in note["text"]:
                    continue
                frag = L(note["text"].split(":", 1)[-1])
                if len(frag) >= 12 and "امس" in src_key and contained(frag, src_key) >= 0.95:
                    if best_note is None or len(frag) > best_note[0]:   # the most specific footnote
                        best_note = (len(frag), note)
            if best_note:
                r["eveningVariantFootnote"] = {"page": best_note[1]["page"], "text": best_note[1]["text"]}

        # Repetition, against the matched book item.
        book_phrases = count_phrases(bitem["arabicText"]) if bitem else []
        book_values = pc.repeat_values(bitem["arabicText"]) if bitem else []
        consistent = None if not bitem else (r["sourceCount"] in book_values or (r["sourceCount"] == 1 and not book_values))
        decision = REPEAT_DECISIONS.get(r["sourceItemId"])
        r["repetition"] = {
            "sourceCount": r["sourceCount"],
            "phase2cCount": bundled_by_id[r["sourceItemId"]]["repetition"]["count"],
            "sourceCountPhrases": count_phrases(r["sourceText"]),
            "bookCountPhrases": book_phrases,
            "bookStatedCounts": book_values,
            "consistentWithBook": consistent,
            "phase2cConflict": any(f.startswith("REPEAT_CONFLICT") for f in bundled_by_id[r["sourceItemId"]]["reviewFlags"]),
        }
        if decision:
            category, count, confidence, reason = decision
            r["repetition"].update({"category": category, "recommendedCount": count,
                                    "confidence": confidence, "reason": reason})

        # Quran: every braced passage of the source, located again with spelling bridged.
        cites = []
        for seg in re.findall(r"\{(.*?)\}", r["sourceText"], re.S):
            hit, n_hits = ortho_locate(seg, qindex)
            entry = {"passage": seg.strip()}
            if hit:
                verses = surahs[hit["surah"]][1][hit["fromAyah"] - 1:hit["toAyah"]]
                literal = pc.locate(seg, pc_index)
                entry.update(hit)
                entry["status"] = ("EXACT" if hit["coversWholeVerses"] else "PARTIAL")
                entry["spellingOnlyDifference"] = literal is None
                entry["incipitOnly"] = "..." in seg or "…" in seg
            else:
                entry["status"] = "UNRESOLVED"
                entry["candidates"] = n_hits
            cites.append(entry)
        r["quranPassages"] = cites
        r["phase2cQuran"] = {
            "status": bundled_by_id[r["sourceItemId"]]["quranStatus"],
            "citations": bundled_by_id[r["sourceItemId"]]["quranCitations"],
        }

        # References: what the source carries vs the book footnotes of the matched item.
        if bitem:
            src_facts = reference_facts(r["sourceReference"])
            book_facts = reference_facts(" ".join(footnote_text(x) for x in bitem["footnotes"]))
            r["referenceComparison"] = {
                "source": src_facts,
                "book": book_facts,
                "missingInSource": {k: sorted(set(book_facts[k]) - set(src_facts[k])) for k in book_facts},
                "notInBook": {k: sorted(set(src_facts[k]) - set(book_facts[k])) for k in src_facts},
            }

    # Book side: every numbered book item and the source items carrying it.
    book_rows = []
    for number in sorted(book_by_number):
        chap, bitem = book_by_number[number]
        carriers = [r for r in rows if r["matchedBookNumber"] == number]
        joined = {}
        for r in carriers:
            joined.setdefault(r["sourceChapter"], []).append(L(r["sourceText"]))
        # Coverage of the book's dhikr wording; instructions such as (ثلاث مرات) are left
        # out because the source moves them into its Count field.
        coverage = max((contained(L(book_core(bitem["arabicText"])), "".join(v)) for v in joined.values()), default=0.0)
        book_rows.append({
            "bookItemNumber": number,
            "bookChapterNumber": chap["number"],
            "chapterLocalNumber": bitem["chapterLocalNumber"],
            "inOfficialItemList": number in official,
            "bookText": bitem["arabicText"],
            "bookFootnotes": [footnote_text(n) for n in bitem["footnotes"]],
            "sourceItemIds": [r["sourceItemId"] for r in carriers],
            "phase2cSourceItemIds": [r["sourceItemId"] for r in rows if r["sourceBookNumber"] == number],
            "coverage": round(coverage, 3),
            "bracketedAdditions": [
                {"text": seg.strip(),
                 "inSource": max((contained(L(seg), "".join(v)) for v in joined.values()), default=0.0) >= 0.95}
                for seg in re.findall(r"\[([^\]]+)\]", bitem["arabicText"]) if len(L(seg)) >= 4],
            "repeatPhrasesInBook": pc.repeat_values(bitem["arabicText"]),
        })

    # Recommended action and review priority per item (P0 before UI/content freeze,
    # P1 before release, P2 may stay review-required). Religious wording is never P2.
    for r in rows:
        actions, p = [], []
        evening = "eveningVariantFootnote" in r or (
            r["matchType"] == "UNMATCHED" and any(h["where"] == "FOOTNOTE" for h in r.get("foundOutsideNumberedText", [])))
        if evening:
            actions.append("LINK_AS_EVENING_VARIANT_FROM_BOOK_FOOTNOTE"); p.append("P1")
        if r["matchType"] == "UNMATCHED" and not evening:
            where = {h["where"] for h in r.get("foundOutsideNumberedText", [])}
            if "CHAPTER_INTRODUCTION" in where:
                actions.append("DECIDE_CHAPTER_INTRODUCTION_AS_ITEM"); p.append("P1")
            else:
                actions.append("REVIEW_UNMATCHED"); p.append("P0")
        if r["sourceBookNumber"] != r["matchedBookNumber"] and r["matchedBookNumber"] is not None:
            actions.append("CORRECT_BOOK_ITEM_NUMBER"); p.append("P0")
        if "ORDER_DIFFERENCE" in r["matchQualities"]:
            actions.append("RESTORE_BOOK_ORDER_OR_ACCEPT"); p.append("P0")
        if "SPLIT" in r["matchQualities"]:
            actions.append("CONFIRM_SPLIT_PART"); p.append("P1")
        if "MERGED" in r["matchQualities"]:
            actions.append("REVIEW_MERGE"); p.append("P0")
        if any(not x["inSource"] for x in r.get("bookBracketedAdditions", [])):
            actions.append("DECIDE_BRACKETED_ADDITION"); p.append("P0")
        if r["dhikrWordingDifferences"] and not evening and "SPLIT" not in r["matchQualities"]:
            actions.append("REVIEW_DHIKR_WORDING"); p.append("P0")
        if evening:
            pass
        elif r["matchedBookNumber"] is not None and r["sourceInBook"] < MATCH_FWD and not r["shortText"]:
            actions.append("REVIEW_TEXT_NOT_IN_BOOK_ITEM"); p.append("P0")
        elif "WORDING_DIFFERENCE" in r["matchQualities"] and ("SPLIT" not in r["matchQualities"] or r["shortText"]):
            actions.append("REVIEW_WORDING"); p.append("P1")
        rep = r["repetition"]
        if rep.get("category"):
            if rep["recommendedCount"] is None or rep["confidence"] != "HIGH":
                actions.append("DECIDE_REPEAT_COUNT"); p.append("P0")
            else:
                actions.append("APPLY_RECOMMENDED_REPEAT_COUNT"); p.append("P0")
        if any(c["status"] == "UNRESOLVED" for c in r["quranPassages"]):
            actions.append("RESOLVE_QURAN_PASSAGE"); p.append("P0")
        if any(c.get("spellingOnlyDifference") or c.get("incipitOnly") for c in r["quranPassages"]) or \
                any(c["match"] == "FUZZY" for c in r["phase2cQuran"]["citations"]) or r["phase2cQuran"]["status"] == "PARTIAL":
            actions.append("CORRECT_QURAN_CITATION"); p.append("P0")
        ref = r.get("referenceComparison")
        if ref and (ref["missingInSource"]["volumePages"] and ref["notInBook"]["volumePages"]):
            actions.append("CHECK_VOLUME_PAGE"); p.append("P1")
        if ref and (ref["missingInSource"]["hadithNumbers"] or ref["missingInSource"]["collections"] or ref["missingInSource"]["gradings"]):
            actions.append("ADD_MISSING_TAKHRIJ_DETAIL"); p.append("P1")
        if r["matchType"] == "SHORT_TEXT" and not actions:
            actions.append("CONFIRM_SHORT_MATCH"); p.append("P2")
        if "REVIEW_DHIKR_WORDING" in actions and "REVIEW_WORDING" in actions:
            del p[actions.index("REVIEW_WORDING")]
            actions.remove("REVIEW_WORDING")
        r["recommendedAction"] = actions or ["KEEP"]
        r["reviewPriority"] = min(p) if p else None
        r["reviewFlag"] = "CONTENT_REVIEW_REQUIRED"

    # Phase 2C's open questions, answered from the rows above.
    by_id = {r["sourceItemId"]: r for r in rows}
    by_book = {b["bookItemNumber"]: b for b in book_rows}
    missing_2c = [b["bookItemNumber"] for b in book_rows if not b["phase2cSourceItemIds"]]
    unmatched_2c = [r["sourceItemId"] for r in rows if r["sourceBookNumber"] is None]
    missing_resolution = []
    for n in missing_2c:
        carriers = by_book[n]["sourceItemIds"]
        missing_resolution.append({
            "bookItemNumber": n,
            "bookText": by_book[n]["bookText"],
            "inOfficialItemList": by_book[n]["inOfficialItemList"],
            "nowCarriedBy": carriers,
            "matchTypes": [by_id[c]["matchType"] for c in carriers],
            "phase2cCarriedBy": [r["sourceItemId"] for r in rows if r["sourceBookNumber"] == n],
            "result": "PRESENT_IN_SOURCE" if carriers else "GENUINELY_MISSING",
        })
    unmatched_resolution = []
    for sid in unmatched_2c:
        r = by_id[sid]
        unmatched_resolution.append({
            "sourceItemId": sid,
            "matchedBookNumber": r["matchedBookNumber"],
            "matchType": r["matchType"],
            "foundOutsideNumberedText": [{k: v for k, v in h.items() if k != "footnote"} for h in r.get("foundOutsideNumberedText", [])],
            "eveningVariantFootnote": r.get("eveningVariantFootnote"),
            "recommendedAction": r["recommendedAction"],
        })
    priorities = {}
    for r in rows:
        priorities[str(r["reviewPriority"])] = priorities.get(str(r["reviewPriority"]), 0) + 1
    match_types = {}
    for r in rows:
        match_types[r["matchType"]] = match_types.get(r["matchType"], 0) + 1
    summary = {
        "sourceChapters": len(titles),
        "sourceItems": len(rows),
        "bookChapters": len(book),
        "bookItems": len(book_rows),
        "bookChaptersCarried": len({r["bookChapterNumber"] for r in rows if r["bookChapterNumber"]}),
        "sourceChaptersSharingABookChapter": sorted({c for v in pair_chapters.values() if len(v) > 1 for c in v}),
        "matchTypes": match_types,
        "matchedToBookNumber": sum(1 for r in rows if r["matchedBookNumber"] is not None),
        "bookNumbersCarried": sum(1 for b in book_rows if b["sourceItemIds"]),
        "bookNumbersWithoutCarrier": [b["bookItemNumber"] for b in book_rows if not b["sourceItemIds"]],
        "phase2cBookNumberChanged": sum(1 for r in rows if r["sourceBookNumber"] != r["matchedBookNumber"]),
        "officialListNumbers": len(official),
        "reviewPriorities": priorities,
        "repeatConflictsPhase2c": sum(1 for r in rows if r["repetition"]["phase2cConflict"]),
        "quranPassagesBraced": sum(len(r["quranPassages"]) for r in rows),
        "itemsMissingHadithNumbers": sum(1 for r in rows if r.get("referenceComparison") and r["referenceComparison"]["missingInSource"]["hadithNumbers"]),
        "itemsWithVolumePageMismatch": sum(1 for r in rows if "CHECK_VOLUME_PAGE" in r["recommendedAction"]),
    }

    out = {
        "formatVersion": 1,
        "primary": "Packages/IslamicCore/Upstream/hisn/asellam/hisn.json",
        "crossCheck": cross["crossCheck"],
        "generatedBy": "tools/content/hisn/reconcile.py",
        "note": "Analysis only. Nothing here changes bundled text, counts or references.",
        "summary": summary,
        "phase2cMissingBookNumbers": missing_resolution,
        "phase2cUnmatchedItems": unmatched_resolution,
        "chapters": [{
            "sourceChapter": ci + 1,
            "sourceTitle": title,
            "bookChapterNumber": cross["chapters"][ci]["bookChapterNumber"],
            "bookTitle": book[cross["chapters"][ci]["bookChapterNumber"] - 1]["titleArabic"],
            "titleDifference": L(title) != L(book[cross["chapters"][ci]["bookChapterNumber"] - 1]["titleArabic"]),
            "sourceItems": len(primary[title]["Adhkar"]),
            "bookItems": len(book[cross["chapters"][ci]["bookChapterNumber"] - 1]["items"]),
        } for ci, title in enumerate(titles)],
        "frontMatter": {
            "presentInPrimarySource": False,
            "presentInCrossCheck": bool(front.get("text")),
            "sections": ["المقدمة", "فضل الذكر"],
            "letters": len(L(front.get("text", ""))),
            "footnotes": len(front.get("footnotes", [])),
        },
        "items": rows,
        "bookItems": book_rows,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    types = {}
    for r in rows:
        types[r["matchType"]] = types.get(r["matchType"], 0) + 1
    print(json.dumps(summary, ensure_ascii=False))
    print("book numbers without a carrier:", [b["bookItemNumber"] for b in book_rows if not b["sourceItemIds"]])


if __name__ == "__main__":
    main()
