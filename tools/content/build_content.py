#!/usr/bin/env python3
"""Builds the bundled IslamicCore content JSON from the unmodified upstream sources.

Inputs (never edited by this script):
  Packages/IslamicCore/Upstream/tanzil/quran-uthmani.xml  Tanzil Uthmani text, verbatim
  Packages/IslamicCore/Upstream/tanzil/quran-data.xml     Tanzil surah metadata
  tools/content/adhkar.source.json, tools/content/duas.source.json
  Packages/IslamicCore/Upstream/hisn/asellam/hisn.json    Hisn Al-Muslim text (MIT repository), verbatim
  tools/content/hisn.crosscheck.json                      per-item book cross-check (prepare_crosscheck.py)
  tools/content/hisn.reconciliation.json                  Phase 2D book reconciliation (hisn/reconcile.py)
  tools/content/hisn.corrections.json                     Phase 2E correction manifest (hand-reviewed)
  tools/content/hisn.editorial_review.json                Phase 2F editorial decisions on the P0 findings

Outputs (deterministic, UTF-8, sorted, indented):
  Packages/IslamicCore/Sources/IslamicCore/Resources/Content/{quran,adhkar,duas,hisn}.json

Quran text is copied character for character. Quranic adhkar and duas reference verses
and get their text from the same Tanzil file, so nothing Quranic is typed by hand.

Hisn pipeline: upstream text -> cross-check mapping -> correction manifest -> editorial review -> hisn.json.
Only manifest entries with an accepted status change a value; every other entry is recorded
and checked. The Arabic text is never changed unless an entry is an ACCEPTED_TEXT_CORRECTION.

Run: python3 tools/content/build_content.py [--check]
--check fails if the committed JSON differs from what the script would write.
"""
import copy
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / "Packages/IslamicCore/Upstream/tanzil"
OUT = ROOT / "Packages/IslamicCore/Sources/IslamicCore/Resources/Content"
SRC = ROOT / "tools/content"

FORMAT_VERSION = 1
REVIEW_REQUIRED = "CONTENT_REVIEW_REQUIRED"
QURAN_VERBATIM = "QURAN_VERBATIM_TANZIL"

TANZIL_SOURCE = {
    "name": "Tanzil Quran Text (Uthmani, Version 1.1)",
    "url": "https://tanzil.net",
    "license": "Creative Commons Attribution 3.0. Verbatim copies only; changing the text is not allowed. See ATTRIBUTION.md.",
    "upstreamFile": "Upstream/tanzil/quran-uthmani.xml",
}


def load_quran():
    text_root = ET.parse(UPSTREAM / "quran-uthmani.xml").getroot()
    meta_root = ET.parse(UPSTREAM / "quran-data.xml").getroot()
    meta = {int(s.get("index")): s for s in meta_root.find("suras").findall("sura")}
    surahs = []
    for sura in text_root.findall("sura"):
        sid = int(sura.get("index"))
        m = meta[sid]
        ayas = sura.findall("aya")
        assert [int(a.get("index")) for a in ayas] == list(range(1, len(ayas) + 1)), sid
        assert int(m.get("ayas")) == len(ayas), sid
        assert m.get("name") == sura.get("name"), sid
        bismillah = ayas[0].get("bismillah")
        surahs.append({
            "id": sid,
            "nameArabic": sura.get("name"),
            "nameTransliteration": m.get("tname"),
            "nameEnglish": m.get("ename"),
            "revelationType": m.get("type").lower(),
            "revelationOrder": int(m.get("order")),
            "ayahCount": len(ayas),
            "bismillah": bismillah,
            "verses": [a.get("text") for a in ayas],
        })
    assert len(surahs) == 114
    assert sum(s["ayahCount"] for s in surahs) == 6236
    return surahs


def quran_text(surahs, ref):
    verses = surahs[ref["surah"] - 1]["verses"]
    assert 1 <= ref["fromAyah"] <= ref["toAyah"] <= len(verses), ref
    # Whole verses joined by a single space; each verse is unchanged.
    return " ".join(verses[ref["fromAyah"] - 1: ref["toAyah"]])


def ref_label(surahs, ref):
    name = surahs[ref["surah"] - 1]["nameArabic"]
    a, b = ref["fromAyah"], ref["toAyah"]
    return f"سورة {name}: {a}" if a == b else f"سورة {name}: {a}-{b}"


def build_items(surahs, raw_items, prefix, owner_key, owner_id, with_repeat):
    items = []
    for order, raw in enumerate(raw_items, start=1):
        ref = raw.get("quranRef")
        if ref:
            assert "arabicText" not in raw, f"{prefix}-{order}: Quranic text must come from Tanzil"
            text = quran_text(surahs, ref)
            source = raw.get("source") or ref_label(surahs, ref)
            status = QURAN_VERBATIM
        else:
            text = raw["arabicText"]
            source = raw["source"]
            status = REVIEW_REQUIRED
        item = {
            "id": f"{prefix}-{order:03d}",
            owner_key: owner_id,
            "order": order,
            "arabicText": text,
            "source": source,
            "quranRef": ref,
            "reviewStatus": status,
        }
        if with_repeat:
            item["repeatCount"] = raw.get("repeatCount", 1)
        items.append(item)
    return items


def build():
    surahs = load_quran()
    quran = {"formatVersion": FORMAT_VERSION, "source": TANZIL_SOURCE, "surahs": surahs}

    adhkar_src = json.loads((SRC / "adhkar.source.json").read_text(encoding="utf-8"))
    adhkar = {
        "formatVersion": FORMAT_VERSION,
        "contentVersion": adhkar_src["contentVersion"],
        "groups": [
            {
                "id": g["id"],
                "titleArabic": g["titleArabic"],
                "items": build_items(surahs, g["items"], f"dhikr-{g['id']}", "group", g["id"], True),
            }
            for g in adhkar_src["groups"]
        ],
    }

    duas_src = json.loads((SRC / "duas.source.json").read_text(encoding="utf-8"))
    duas = {
        "formatVersion": FORMAT_VERSION,
        "contentVersion": duas_src["contentVersion"],
        "categories": [
            {
                "id": c["id"],
                "titleArabic": c["titleArabic"],
                "items": build_items(surahs, c["items"], f"dua-{c['id']}", "category", c["id"], False),
            }
            for c in duas_src["categories"]
        ],
    }
    hisn = build_hisn(surahs)
    return {"quran.json": quran, "adhkar.json": adhkar, "duas.json": duas, "hisn.json": hisn}


HISN_UPSTREAM = ROOT / "Packages/IslamicCore/Upstream/hisn/asellam/hisn.json"
HISN_PDF_SHA256 = "50d539829d29a66215e4bd048aec982cd9a7ab87fcd87f6410765c69f829cbb9"
RIGHTS_PENDING = "PENDING_PRE_RELEASE_REVIEW"
# Collection names indexed for search; the reference text itself is kept verbatim.
HADITH_COLLECTIONS = ["البخاري", "مسلم", "أبو داود", "الترمذي", "النسائي", "ابن ماجه", "أحمد",
                      "الحاكم", "ابن حبان", "ابن السني", "الطبراني", "البيهقي", "مالك", "الدارمي",
                      "ابن خزيمة", "البزار", "عبد الرزاق", "ابن أبي شيبة", "أبو يعلى"]
ARABIC_MARKS = re.compile(r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]")


def search_text(text):
    """Search key only, never shown: no marks or tatweel, one alef form, ى→ي, ة→ه, letters and spaces."""
    key = ARABIC_MARKS.sub("", text)
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ى", "ي"), ("ة", "ه")):
        key = key.replace(a, b)
    key = re.sub(r"[^\u0621-\u064A ]+", " ", key)
    return re.sub(r" +", " ", key).strip()


def build_hisn(surahs):
    raw = HISN_UPSTREAM.read_bytes()
    upstream = json.loads(raw.decode("utf-8"))
    cross = json.loads((SRC / "hisn.crosscheck.json").read_text(encoding="utf-8"))
    titles = list(upstream)
    assert [c["titleArabic"] for c in cross["chapters"]] == titles, "crosscheck is stale: rerun prepare_crosscheck.py"
    chapters = []
    for number, (title, cc) in enumerate(zip(titles, cross["chapters"]), start=1):
        chapter_id = f"hisn-ch-{number:03d}"
        source_items = upstream[title]["Adhkar"]
        assert len(source_items) == len(cc["items"]), title
        items = []
        for order, (raw_item, check) in enumerate(zip(source_items, cc["items"]), start=1):
            text = raw_item["Text"]
            assert text.strip() and "\ufffd" not in text, f"{chapter_id}/{order}: empty or broken text"
            source_count = raw_item["Count"]
            assert isinstance(source_count, int) and source_count >= 1, f"{chapter_id}/{order}: Count"
            # The source's count is kept only where the book text does not contradict it.
            count = None if check["repeatConsistent"] is False else source_count
            citations = []
            for c in check["quranCitations"]:
                assert 1 <= c["fromAyah"] <= c["toAyah"] <= surahs[c["surah"] - 1]["ayahCount"], c
                citations.append({
                    "reference": {"surah": c["surah"], "fromAyah": c["fromAyah"], "toAyah": c["toAyah"]},
                    "coversWholeVerses": c["wholeVerses"],
                    "match": c["match"],
                    "recitesWholeSurah": False,
                })
            reference = raw_item["Reference"].strip()
            items.append({
                "id": f"hisn-{number:03d}-{order:02d}",
                "chapterId": chapter_id,
                "order": order,
                "bookItemNumber": check["bookItemNumber"],
                "arabicText": text,
                "searchText": search_text(text),
                "repetition": {
                    "count": count,
                    "sourceCount": source_count,
                    "bookStatedCounts": check["bookRepeatValues"],
                    "reviewStatus": REVIEW_REQUIRED,
                },
                "references": [{
                    "originalText": reference,
                    "collections": [c for c in HADITH_COLLECTIONS if c in ARABIC_MARKS.sub("", reference)],
                }] if reference else [],
                "quranCitations": citations,
                "quranStatus": check["quran"],
                "reviewFlags": check["flags"],
                "reviewStatus": REVIEW_REQUIRED,
                "bookItemRelation": None,
                "corrections": {"applied": [], "open": []},
                "nonRecitationText": [],
                "editorialReviews": [],
            })
        chapters.append({
            "id": chapter_id,
            "number": number,
            "titleArabic": title,
            "searchText": search_text(title),
            "bookChapterNumber": cc["bookChapterNumber"],
            "presentationSection": None,
            "items": items,
        })
    corrections = apply_hisn_corrections(chapters, surahs, hashlib.sha256(raw).hexdigest())
    editorial_review = apply_hisn_editorial_review(chapters, surahs)
    return {
        "formatVersion": FORMAT_VERSION,
        "contentVersion": 1,
        "book": {
            "id": "hisn-al-muslim",
            "titleArabic": "حصن المسلم من أذكار الكتاب والسنة",
            "author": "سعيد بن علي بن وهف القحطاني",
            "provenance": {
                "primarySource": {
                    "name": "asellam/HisnElMuslim (hisn.json)",
                    "url": "https://github.com/asellam/HisnElMuslim",
                    "license": "MIT (the repository's licence for its transcription; not a grant from the book's rights holder)",
                    "edition": "Printed edition published by دار السجلات, per the repository README; edition number not stated",
                    "upstreamFile": "Upstream/hisn/asellam/hisn.json",
                    "sha256": hashlib.sha256(raw).hexdigest(),
                    "retrieved": "2026-10-08",
                },
                "crossCheck": {
                    "name": "Shamela transcription of the Safeer / Al-Juraisy print, and the author's official item list",
                    "urls": ["https://shamela.ws/book/31307", "https://binwahaf.com/ar/audio-book-series/897/"],
                    "bookChapters": cross["bookChapters"],
                    "bookItems": cross["bookItems"],
                },
                "canonicalEdition": {
                    "name": "Author's official PDF",
                    "url": "https://binwahaf.com/ar/book/854/",
                    "sha256": HISN_PDF_SHA256,
                    "comparison": "NOT_YET_COMPARED",
                },
                "corrections": corrections,
                "editorialReview": editorial_review,
            },
            "attribution": {
                "sourceTitle": "حصن المسلم من أذكار الكتاب والسنة",
                "author": "سعيد بن علي بن وهف القحطاني",
                "edition": None,
                "sourceURL": "https://binwahaf.com/ar/book/854/",
                "attributionText": None,
                "rightsStatus": RIGHTS_PENDING,
            },
        },
        "chapters": chapters,
    }


# ---------------------------------------------------------------------------
# Phase 2E correction manifest
# ---------------------------------------------------------------------------
HISN_MANIFEST = SRC / "hisn.corrections.json"
HISN_RECONCILIATION = SRC / "hisn.reconciliation.json"
CORRECTION_TYPES = {"BOOK_ITEM_NUMBER", "CANONICAL_ORDER", "REPETITION_COUNT", "QURAN_CITATION",
                    "BOOK_ITEM_RELATION", "TEXT_DISCREPANCY", "NON_DHIKR_TEXT", "REFERENCE_METADATA",
                    "PRESENTATION_SECTION"}
APPLIED_STATUSES = {"ACCEPTED", "ACCEPTED_TEXT_CORRECTION"}
OBSERVED_STATUSES = {"OBSERVED_DIFFERENCE", "OBSERVATION"}
PENDING_STATUSES = {"PENDING_DECISION"}
REJECTED_STATUSES = {"REJECTED"}
CONFIDENCES = {"HIGH", "MEDIUM", "LOW"}
PRIORITIES = {"P0", "P1", "P2"}
RELATIONS = {"DIRECT", "SPLIT_PART", "EVENING_VARIANT", "CHAPTER_INTRODUCTION"}
SECTIONS = {"MORNING", "EVENING"}
# Types whose accepted entries change a value, and the value they own (for conflict checks).
APPLIED_FIELD = {"BOOK_ITEM_NUMBER": "bookItemNumber", "REPETITION_COUNT": "repetition.count",
                 "QURAN_CITATION": "quranCitations", "BOOK_ITEM_RELATION": "bookItemRelation",
                 "PRESENTATION_SECTION": "presentationSection", "TEXT_DISCREPANCY": "arabicText",
                 "CANONICAL_ORDER": "canonicalOrder"}
# Types that only record what was found; they may never be ACCEPTED.
RECORD_ONLY = {"NON_DHIKR_TEXT", "REFERENCE_METADATA"}


class CorrectionError(Exception):
    pass


def fail(entry, message):
    raise CorrectionError(f"{entry.get('id', '?')}: {message}" if isinstance(entry, dict) else f"{entry}: {message}")


def check_entry(c, items, chapters_by_id):
    """Schema, status and evidence rules every entry must meet, applied or not."""
    for key in ("id", "type", "target", "evidence", "confidence", "reviewStatus", "reviewPriority"):
        if key not in c:
            fail(c, f"missing {key}")
    if not re.fullmatch(r"HISN-CORR-\d{3}", c["id"]):
        fail(c, "id must be HISN-CORR-NNN")
    if c["type"] not in CORRECTION_TYPES:
        fail(c, f"unknown type {c['type']}")
    status = c["reviewStatus"]
    if status not in APPLIED_STATUSES | OBSERVED_STATUSES | PENDING_STATUSES | REJECTED_STATUSES:
        fail(c, f"unknown reviewStatus {status}")
    if c["confidence"] not in CONFIDENCES:
        fail(c, f"unknown confidence {c['confidence']}")
    if c["reviewPriority"] not in PRIORITIES:
        fail(c, f"unknown reviewPriority {c['reviewPriority']}")
    ev = c["evidence"]
    for key in ("source", "reference", "reason"):
        if not isinstance(ev.get(key), str) or not ev[key].strip():
            fail(c, f"evidence.{key} is missing")
    if len(ev["reason"]) < 30:
        fail(c, "evidence.reason is too vague")
    if status in REJECTED_STATUSES and not re.fullmatch(r"HISN-REVIEW-\d{3}", c.get("rejectedBy") or ""):
        fail(c, "a REJECTED entry names the editorial review that declined it (rejectedBy)")
    if status in APPLIED_STATUSES:
        if c["confidence"] == "LOW":
            fail(c, "a LOW confidence entry cannot be accepted")
        if c["confidence"] == "MEDIUM" and not c.get("acceptedBy"):
            fail(c, "a MEDIUM confidence entry needs acceptedBy to be accepted")
        if c["type"] in RECORD_ONLY:
            fail(c, f"{c['type']} entries are recorded only and cannot be accepted")
        if c["type"] == "TEXT_DISCREPANCY" and status != "ACCEPTED_TEXT_CORRECTION":
            fail(c, "a text change must be an ACCEPTED_TEXT_CORRECTION")
        if status == "ACCEPTED_TEXT_CORRECTION" and (c["type"] != "TEXT_DISCREPANCY" or not c.get("acceptedBy")):
            fail(c, "ACCEPTED_TEXT_CORRECTION is only for TEXT_DISCREPANCY and needs acceptedBy")
        if c["type"] == "BOOK_ITEM_RELATION" and c["after"]["bookItemRelation"] == "SPLIT_PART":
            fail(c, "SPLIT_PART is derived from the mapping; record split groups as OBSERVATION")
    target = c["target"]
    ids = [target["sourceItemId"]] if "sourceItemId" in target else target.get("sourceItemIds", [])
    if c.get("sourceItemId") != target.get("sourceItemId"):
        fail(c, "sourceItemId does not match target")
    for sid in ids:
        if sid not in items:
            fail(c, f"item {sid} does not exist")
    if "chapterId" in target and target["chapterId"] not in chapters_by_id:
        fail(c, f"chapter {target['chapterId']} does not exist")
    if not ids and "chapterId" not in target and target.get("scope") != "BOOK":
        fail(c, "target names no item, chapter or BOOK scope")
    return ids


def check_quran(c, surahs, after):
    if after["quranStatus"] not in ("RESOLVED", "PARTIAL") or not after["quranCitations"]:
        fail(c, "a Quran correction must resolve to at least one citation")
    for cit in after["quranCitations"]:
        ref = cit["reference"]
        if not 1 <= ref["surah"] <= len(surahs):
            fail(c, f"invalid surah {ref['surah']}")
        if not 1 <= ref["fromAyah"] <= ref["toAyah"] <= surahs[ref["surah"] - 1]["ayahCount"]:
            fail(c, f"invalid Quran reference {ref}")
        if cit["match"] not in ("EXACT", "FUZZY") or not isinstance(cit["coversWholeVerses"], bool) \
                or not isinstance(cit["recitesWholeSurah"], bool):
            fail(c, f"invalid citation {cit}")


def canonical_key_order(chapter):
    """Book order inside one presentation section: by book item number, unnumbered items stay
    after the item before them, a chapter introduction comes first. Stable on display order."""
    keyed, last = [], 0
    for item in chapter["items"]:
        if item["bookItemRelation"] == "CHAPTER_INTRODUCTION":
            key = 0
        else:
            key = item["bookItemNumber"] if item["bookItemNumber"] is not None else last
            last = key
        keyed.append((key, item["order"], item["id"]))
    return keyed


def apply_hisn_corrections(chapters, surahs, upstream_sha):
    manifest_raw = HISN_MANIFEST.read_bytes()
    manifest = json.loads(manifest_raw.decode("utf-8"))
    rec = json.loads(HISN_RECONCILIATION.read_text(encoding="utf-8"))
    try:
        return _apply(manifest, manifest_raw, rec, chapters, surahs, upstream_sha)
    except CorrectionError as error:
        sys.exit(f"Hisn correction manifest rejected: {error}")


def _apply(manifest, manifest_raw, rec, chapters, surahs, upstream_sha):
    if manifest.get("schemaVersion") != 1:
        fail("manifest", "schemaVersion must be 1")
    if manifest["source"].get("upstreamSha256") != upstream_sha:
        fail("manifest", f"upstream hisn.json changed: manifest {manifest['source'].get('upstreamSha256')}, file {upstream_sha}")
    book_total = rec["summary"]["bookItems"]
    chapter_total = rec["summary"]["bookChapters"]
    book_chapter_of = {b["bookItemNumber"]: b["bookChapterNumber"] for b in rec["bookItems"]}
    if sorted(book_chapter_of) != list(range(1, book_total + 1)):
        fail("reconciliation", "book item list is not 1..N")

    chapters_by_id = {ch["id"]: ch for ch in chapters}
    items = {it["id"]: it for ch in chapters for it in ch["items"]}
    chapter_of = {it["id"]: chapters_by_id[it["chapterId"]] for it in items.values()}
    # Every `before` is checked against the mapped value, before any entry is applied.
    mapped = copy.deepcopy(items)

    seen_ids, owned = set(), {}
    entries = manifest["corrections"]
    for c in entries:
        if c["id"] in seen_ids:
            fail(c, "duplicate id")
        seen_ids.add(c["id"])
        ids = check_entry(c, items, chapters_by_id)
        status, kind, before, after = c["reviewStatus"], c["type"], c.get("before"), c.get("after")
        applied = status in APPLIED_STATUSES

        # Value checks run for pending entries too, so accepting one later cannot break the build.
        if kind == "BOOK_ITEM_NUMBER":
            (sid,) = ids
            if mapped[sid]["bookItemNumber"] != before["bookItemNumber"]:
                fail(c, f"before {before} does not match the mapped value {mapped[sid]['bookItemNumber']}")
            number = after["bookItemNumber"]
            if not isinstance(number, int) or not 1 <= number <= book_total:
                fail(c, f"book item number {number} is outside 1...{book_total}")
            if book_chapter_of[number] != chapter_of[sid]["bookChapterNumber"]:
                fail(c, f"book item {number} is in book chapter {book_chapter_of[number]}, not {chapter_of[sid]['bookChapterNumber']}")
        elif kind == "REPETITION_COUNT":
            (sid,) = ids
            if mapped[sid]["repetition"]["count"] != before["count"]:
                fail(c, f"before {before} does not match the mapped count {mapped[sid]['repetition']['count']}")
            if after["count"] is not None and (not isinstance(after["count"], int) or after["count"] < 1):
                fail(c, f"invalid count {after['count']}")
        elif kind == "QURAN_CITATION":
            (sid,) = ids
            if mapped[sid]["quranStatus"] != before["quranStatus"] or \
                    [{k: v for k, v in x.items() if k != "recitesWholeSurah"} for x in mapped[sid]["quranCitations"]] != before["quranCitations"]:
                fail(c, "before does not match the current citations")
            check_quran(c, surahs, after)
        elif kind == "BOOK_ITEM_RELATION":
            if after["bookItemRelation"] not in RELATIONS:
                fail(c, f"unknown relation {after['bookItemRelation']}")
        elif kind == "PRESENTATION_SECTION":
            ch = chapters_by_id[c["target"]["chapterId"]]
            if after["presentationSection"] not in SECTIONS or after["bookChapterNumber"] != ch["bookChapterNumber"]:
                fail(c, "presentation section does not match the chapter")
        elif kind == "CANONICAL_ORDER":
            if before["displayOrder"] != sorted(ids, key=lambda i: (chapter_of[i]["number"], items[i]["order"])) \
                    or sorted(after["canonicalOrder"]) != sorted(ids):
                fail(c, "displayOrder/canonicalOrder do not list the target items")
        elif kind == "TEXT_DISCREPANCY":
            (sid,) = ids
            if before["arabicText"] != mapped[sid]["arabicText"]:
                fail(c, "before text does not match the source text")
            if applied and (not isinstance(after, dict) or not after.get("arabicText", "").strip()):
                fail(c, "an accepted text correction needs the full replacement text")
        elif kind == "NON_DHIKR_TEXT":
            (sid,) = ids
            if before["arabicText"] != mapped[sid]["arabicText"] or c["evidence"]["sourceExcerpt"] not in mapped[sid]["arabicText"]:
                fail(c, "the recorded excerpt is not in the source text")

        if not applied:
            if status not in OBSERVED_STATUSES - {"OBSERVED_DIFFERENCE"} | REJECTED_STATUSES:
                for sid in ids:
                    items[sid]["corrections"]["open"].append(c["id"])
            continue
        targets = ids or [c["target"]["chapterId"]]
        for t in targets:
            key = (t, APPLIED_FIELD[kind])
            if key in owned:
                fail(c, f"conflicts with {owned[key]} on {key[1]} of {t}")
            owned[key] = c["id"]
        for sid in ids:
            items[sid]["corrections"]["applied"].append(c["id"])
        if kind == "BOOK_ITEM_NUMBER":
            items[ids[0]]["bookItemNumber"] = after["bookItemNumber"]
        elif kind == "REPETITION_COUNT":
            items[ids[0]]["repetition"]["count"] = after["count"]
        elif kind == "QURAN_CITATION":
            items[ids[0]]["quranStatus"] = after["quranStatus"]
            items[ids[0]]["quranCitations"] = after["quranCitations"]
        elif kind == "BOOK_ITEM_RELATION":
            for sid in ids:
                items[sid]["bookItemRelation"] = after["bookItemRelation"]
        elif kind == "PRESENTATION_SECTION":
            chapters_by_id[c["target"]["chapterId"]]["presentationSection"] = after["presentationSection"]
        elif kind == "TEXT_DISCREPANCY":
            item = items[ids[0]]
            item["arabicText"] = after["arabicText"]
            item["searchText"] = search_text(after["arabicText"])

    # Canonical structure: 132 book chapters, every book number 1...N carried.
    if sorted({ch["bookChapterNumber"] for ch in chapters}) != list(range(1, chapter_total + 1)):
        fail("structure", f"presentation sections do not cover book chapters 1...{chapter_total}")
    for ch in chapters:
        siblings = [x for x in chapters if x["bookChapterNumber"] == ch["bookChapterNumber"]]
        sections = [x["presentationSection"] for x in siblings]
        if len(siblings) > 1 and (None in sections or len(set(sections)) != len(sections)):
            fail(ch["id"], "a book chapter shown as several sections needs distinct presentation sections")
        if len(siblings) == 1 and ch["presentationSection"] is not None:
            fail(ch["id"], "a single-section chapter has no presentation section")

    carriers = {}
    for item in items.values():
        number = item["bookItemNumber"]
        if number is not None:
            if book_chapter_of[number] != chapter_of[item["id"]]["bookChapterNumber"]:
                fail(item["id"], f"book item {number} belongs to book chapter {book_chapter_of[number]}")
            carriers.setdefault(number, []).append(item)
    missing = sorted(set(range(1, book_total + 1)) - set(carriers))
    if missing:
        fail("structure", f"unmapped canonical book items {missing}")

    # Relations: derive DIRECT / SPLIT_PART, check the explicit ones.
    split_groups = set()
    for number, group in carriers.items():
        by_chapter = {}
        for item in group:
            by_chapter.setdefault(item["chapterId"], []).append(item)
        if len(by_chapter) > 1 and len({chapters_by_id[cid]["presentationSection"] for cid in by_chapter} - {None}) != len(by_chapter):
            fail("structure", f"book item {number} is mapped from unrelated sections {sorted(by_chapter)}")
        for cid, part in by_chapter.items():
            if len(part) > 1:
                orders = [x["order"] for x in part]
                if orders != list(range(orders[0], orders[0] + len(part))):
                    fail("structure", f"book item {number} is mapped twice in {cid} by non-adjacent items")
                if any(x["bookItemRelation"] is not None for x in part):
                    fail("structure", f"split parts of book item {number} carry a contradictory relation")
                split_groups.add((number, tuple(x["id"] for x in part)))
                for x in part:
                    x["bookItemRelation"] = "SPLIT_PART"
    for item in items.values():
        relation = item["bookItemRelation"]
        if relation is None:
            if item["bookItemNumber"] is None:
                fail(item["id"], "has no book item number and no relation")
            item["bookItemRelation"] = relation = "DIRECT"
        if relation == "CHAPTER_INTRODUCTION" and (item["bookItemNumber"] is not None or item["order"] != 1):
            fail(item["id"], "a chapter introduction is the unnumbered first item")
        if relation == "EVENING_VARIANT" and chapter_of[item["id"]]["presentationSection"] != "EVENING":
            fail(item["id"], "an evening variant must be in the evening section")
    observed_splits = {(c["after"]["bookItemNumber"], tuple(c["target"]["sourceItemIds"]))
                       for c in entries if c["type"] == "BOOK_ITEM_RELATION" and c["after"]["bookItemRelation"] == "SPLIT_PART"}
    if observed_splits != split_groups:
        fail("structure", f"split groups differ from the manifest: {sorted(split_groups ^ observed_splits)}")

    # Canonical order: every display/book inversion must be an accepted CANONICAL_ORDER entry.
    order_entries = [c for c in entries if c["type"] == "CANONICAL_ORDER" and c["reviewStatus"] in APPLIED_STATUSES]
    documented = {frozenset(c["target"]["sourceItemIds"]) for c in order_entries}
    canonical = {}
    for ch in chapters:
        keyed = canonical_key_order(ch)
        for i, (ka, _, a) in enumerate(keyed):
            for kb, _, b in keyed[i + 1:]:
                if ka > kb and frozenset((a, b)) not in documented:
                    fail(ch["id"], f"{a} comes after {b} in the book but has no CANONICAL_ORDER entry")
        for rank, (_, _, sid) in enumerate(sorted(keyed), start=1):
            canonical[sid] = rank
    for c in order_entries:
        derived = sorted(c["target"]["sourceItemIds"], key=lambda sid: canonical[sid])
        if derived != c["after"]["canonicalOrder"]:
            fail(c, f"derived canonical order {derived} differs from {c['after']['canonicalOrder']}")

    for item in items.values():
        item["corrections"]["applied"].sort()
        item["corrections"]["open"].sort()
        assert item["reviewStatus"] == REVIEW_REQUIRED and item["repetition"]["reviewStatus"] == REVIEW_REQUIRED

    accepted = [c for c in entries if c["reviewStatus"] in APPLIED_STATUSES]
    observed = [c for c in entries if c["reviewStatus"] in OBSERVED_STATUSES]
    pending = [c for c in entries if c["reviewStatus"] in PENDING_STATUSES]
    rejected = [c for c in entries if c["reviewStatus"] in REJECTED_STATUSES]
    p0 = [c for c in entries if c["reviewPriority"] == "P0"]
    summary = {
        "manifest": "tools/content/hisn.corrections.json",
        "sha256": hashlib.sha256(manifest_raw).hexdigest(),
        "total": len(entries),
        "accepted": len(accepted),
        "observationOnly": len(observed),
        "pendingDecision": len(pending),
        "rejected": len(rejected),
        "p0Accepted": sum(c in accepted for c in p0),
        "p0Pending": sum(c["reviewStatus"] in OBSERVED_STATUSES | PENDING_STATUSES for c in p0),
        "canonicalBookChapters": chapter_total,
        "canonicalBookItems": book_total,
        "presentationSections": len(chapters),
        "displayItems": len(items),
    }
    print("Hisn corrections:\n"
          f"  total {summary['total']}, accepted {summary['accepted']}, observation-only {summary['observationOnly']}, "
          f"pending {summary['pendingDecision']}, rejected {summary['rejected']}, P0 accepted {summary['p0Accepted']}, P0 pending {summary['p0Pending']}\n"
          f"  canonical {chapter_total} chapters / {book_total} items, presentation {len(chapters)} sections / {len(items)} items")
    return summary


# ---------------------------------------------------------------------------
# Phase 2F editorial review
# ---------------------------------------------------------------------------
HISN_EDITORIAL_REVIEW = SRC / "hisn.editorial_review.json"
EDITORIAL_DECISIONS = {"ACCEPT_CORRECTION", "KEEP_SOURCE", "KEEP_NIL", "KEEP_METADATA", "DEFER"}
DECISION_CONFIDENCES = {"HIGH", "MEDIUM", "LOW", "INSUFFICIENT"}
ISSUE_TYPES = {"TEXT_DISCREPANCY", "NON_DHIKR_TEXT", "REPETITION_COUNT"}
TEXT_ROLES = {"NARRATION", "CLOSING", "LABEL", "INSTRUCTION"}
REVIEW_KEYS = ("id", "sourceItemId", "issueType", "question", "sourceText", "bookText", "correctionIds",
               "decision", "decisionConfidence", "evidence", "rationale", "changesApplied",
               "independentReviewer", "reviewStatus")


def apply_hisn_editorial_review(chapters, surahs):
    raw = HISN_EDITORIAL_REVIEW.read_bytes()
    review = json.loads(raw.decode("utf-8"))
    manifest = json.loads(HISN_MANIFEST.read_text(encoding="utf-8"))
    rec = json.loads(HISN_RECONCILIATION.read_text(encoding="utf-8"))
    try:
        return _review(review, raw, manifest, rec, chapters)
    except CorrectionError as error:
        sys.exit(f"Hisn editorial review rejected: {error}")


def check_reviewer(r, reviewer):
    """An independent reviewer is a named person with a dated, referenced sign-off, or null."""
    if reviewer is None:
        return False
    if not isinstance(reviewer, dict) or not all(isinstance(reviewer.get(k), str) and reviewer[k].strip()
                                                 for k in ("name", "role", "date", "signOffReference")):
        fail(r, "independentReviewer must be null or {name, role, date, signOffReference}")
    return True


def _review(review, raw, manifest, rec, chapters):
    if review.get("schemaVersion") != 1 or review.get("phase") != "2F":
        fail("editorial review", "schemaVersion 1 / phase 2F expected")
    if review["source"].get("upstreamSha256") != manifest["source"]["upstreamSha256"]:
        fail("editorial review", "upstream hash differs from the correction manifest")
    books = {b["bookItemNumber"]: b for b in rec["bookItems"]}
    items = {it["id"]: it for ch in chapters for it in ch["items"]}
    corrections = {c["id"]: c for c in manifest["corrections"]}
    seen, covered = set(), set()
    independent = 0
    for r in review["reviews"]:
        for key in REVIEW_KEYS:
            if key not in r:
                fail(r, f"missing {key}")
        if not re.fullmatch(r"HISN-REVIEW-\d{3}", r["id"]) or r["id"] in seen:
            fail(r, "id must be a unique HISN-REVIEW-NNN")
        seen.add(r["id"])
        sid = r["sourceItemId"]
        if sid not in items:
            fail(r, f"item {sid} does not exist")
        item = items[sid]
        if r["issueType"] not in ISSUE_TYPES:
            fail(r, f"unknown issueType {r['issueType']}")
        if r["decision"] not in EDITORIAL_DECISIONS:
            fail(r, f"unknown decision {r['decision']}")
        if r["decisionConfidence"] not in DECISION_CONFIDENCES:
            fail(r, f"unknown decisionConfidence {r['decisionConfidence']}")
        if not r["question"].strip() or len(r["rationale"]) < 30:
            fail(r, "question or rationale missing")
        if not r["evidence"]:
            fail(r, "a decision needs evidence")
        for ev in r["evidence"]:
            for key in ("source", "reference", "finding"):
                if not isinstance(ev.get(key), str) or not ev[key].strip():
                    fail(r, f"evidence.{key} is missing")
        if r["sourceText"] != item["arabicText"] and r["decision"] != "ACCEPT_CORRECTION":
            fail(r, "sourceText is not the item's text")
        if r["bookText"] != books[item["bookItemNumber"]]["bookText"]:
            fail(r, "bookText is not the cross-check text of the item's book number")
        # No invented sign-off: REVIEWED needs a real reviewer, and content stays CONTENT_REVIEW_REQUIRED.
        has_reviewer = check_reviewer(r, r["independentReviewer"])
        independent += has_reviewer
        if r["reviewStatus"] not in ("EDITORIAL_DECISION_RECORDED", "INDEPENDENTLY_REVIEWED") or \
                (r["reviewStatus"] == "INDEPENDENTLY_REVIEWED") != has_reviewer:
            fail(r, "reviewStatus must match the independent reviewer")
        linked = [corrections.get(cid) for cid in r["correctionIds"]]
        if not linked or None in linked or any(c["sourceItemId"] != sid or c["type"] != r["issueType"]
                                               or c["reviewPriority"] != "P0" for c in linked):
            fail(r, "correctionIds must name this item's P0 manifest entries of the same issue type")
        covered.update(r["correctionIds"])
        applied_text = [c for c in linked if c["reviewStatus"] == "ACCEPTED_TEXT_CORRECTION"]
        decision = r["decision"]
        if decision == "ACCEPT_CORRECTION":
            if r["issueType"] == "TEXT_DISCREPANCY" and r["changesApplied"]:
                if not applied_text or any(not c["before"].get("arabicText") or not c["after"].get("arabicText") for c in applied_text):
                    fail(r, "an applied text correction needs an ACCEPTED_TEXT_CORRECTION with exact before/after")
        else:
            if applied_text:
                fail(r, f"{decision} cannot sit on an applied text correction")
            if r["changesApplied"]:
                fail(r, f"{decision} applies no change")
        if decision == "KEEP_NIL":
            if r["issueType"] != "REPETITION_COUNT" or item["repetition"]["count"] is not None \
                    or r.get("repetition", {}).get("count", 0) is not None:
                fail(r, "KEEP_NIL is for repetition and needs a nil count")
            if any(c["reviewStatus"] in APPLIED_STATUSES and c["after"]["count"] is not None for c in linked):
                fail(r, "KEEP_NIL conflicts with an applied count")
        if decision == "KEEP_METADATA":
            pieces = r.get("metadata") or []
            if not pieces:
                fail(r, "KEEP_METADATA needs metadata entries")
            for piece in pieces:
                if piece.get("role") not in TEXT_ROLES:
                    fail(r, f"unknown role {piece.get('role')}")
                if item["arabicText"].count(piece.get("text") or "\0") != 1:
                    fail(r, "a metadata span must occur exactly once, verbatim, in the item text")
                item["nonRecitationText"].append({"role": piece["role"], "text": piece["text"]})
        elif "metadata" in r:
            fail(r, "metadata is only for KEEP_METADATA")
        for c in linked:
            if c["reviewStatus"] == "REJECTED" and c["rejectedBy"] != r["id"]:
                fail(r, f"{c['id']} is rejected by another review")
        item["editorialReviews"].append({"id": r["id"], "issueType": r["issueType"], "decision": decision,
                                          "changesApplied": r["changesApplied"]})
        assert item["reviewStatus"] == REVIEW_REQUIRED

    # Every P0 finding the corrections manifest did not settle has an editorial decision.
    open_p0 = {c["id"] for c in manifest["corrections"]
               if c["reviewPriority"] == "P0" and c["reviewStatus"] not in APPLIED_STATUSES}
    if open_p0 - covered:
        fail("editorial review", f"P0 entries without a decision: {sorted(open_p0 - covered)}")
    for c in manifest["corrections"]:
        if c["reviewStatus"] == "REJECTED" and c["rejectedBy"] not in seen:
            fail(c, f"rejectedBy {c['rejectedBy']} is not a review")
    if review.get("editorialReviewComplete") and independent < len(review["reviews"]):
        fail("editorial review", "editorialReviewComplete needs an independent reviewer on every decision")
    for item in items.values():
        item["nonRecitationText"].sort(key=lambda p: item["arabicText"].index(p["text"]))

    counts = {d: sum(r["decision"] == d for r in review["reviews"]) for d in sorted(EDITORIAL_DECISIONS)}
    summary = {
        "manifest": "tools/content/hisn.editorial_review.json",
        "sha256": hashlib.sha256(raw).hexdigest(),
        "total": len(review["reviews"]),
        "decisions": counts,
        "changesApplied": sum(r["changesApplied"] for r in review["reviews"]),
        "independentlyReviewed": independent,
        "editorialReviewComplete": bool(review.get("editorialReviewComplete")),
    }
    print("Hisn editorial review:\n"
          f"  total {summary['total']}, " + ", ".join(f"{k} {v}" for k, v in counts.items()) +
          f", changes applied {summary['changesApplied']}, independent review {independent}/{summary['total']}")
    return summary


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def main():
    check = "--check" in sys.argv
    outputs = {name: dump(obj) for name, obj in build().items()}
    OUT.mkdir(parents=True, exist_ok=True)
    stale = []
    for name, text in outputs.items():
        path = OUT / name
        if check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(name)
        else:
            path.write_text(text, encoding="utf-8")
    if stale:
        sys.exit(f"Out of date, run tools/content/build_content.py: {', '.join(stale)}")
    print("content " + ("up to date" if check else "written") + ": " + ", ".join(outputs))


if __name__ == "__main__":
    main()
