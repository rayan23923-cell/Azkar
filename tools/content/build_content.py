#!/usr/bin/env python3
"""Builds the bundled IslamicCore content JSON from the unmodified upstream sources.

Inputs (never edited by this script):
  Packages/IslamicCore/Upstream/tanzil/quran-uthmani.xml  Tanzil Uthmani text, verbatim
  Packages/IslamicCore/Upstream/tanzil/quran-data.xml     Tanzil surah metadata
  tools/content/adhkar.source.json, tools/content/duas.source.json
  Packages/IslamicCore/Upstream/hisn/asellam/hisn.json    Hisn Al-Muslim text (MIT repository), verbatim
  tools/content/hisn.crosscheck.json                      per-item book cross-check (prepare_crosscheck.py)

Outputs (deterministic, UTF-8, sorted, indented):
  Packages/IslamicCore/Sources/IslamicCore/Resources/Content/{quran,adhkar,duas,hisn}.json

Quran text is copied character for character. Quranic adhkar and duas reference verses
and get their text from the same Tanzil file, so nothing Quranic is typed by hand.

Run: python3 tools/content/build_content.py [--check]
--check fails if the committed JSON differs from what the script would write.
"""
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
                    "collections": [c for c in HADITH_COLLECTIONS if c in reference],
                }] if reference else [],
                "quranCitations": citations,
                "quranStatus": check["quran"],
                "reviewFlags": check["flags"],
                "reviewStatus": REVIEW_REQUIRED,
            })
        chapters.append({
            "id": chapter_id,
            "number": number,
            "titleArabic": title,
            "searchText": search_text(title),
            "bookChapterNumber": cc["bookChapterNumber"],
            "items": items,
        })
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
