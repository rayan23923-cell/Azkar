#!/usr/bin/env python3
"""Builds the bundled IslamicCore content JSON from the unmodified upstream sources.

Inputs (never edited by this script):
  Packages/IslamicCore/Upstream/tanzil/quran-uthmani.xml  Tanzil Uthmani text, verbatim
  Packages/IslamicCore/Upstream/tanzil/quran-data.xml     Tanzil surah metadata
  tools/content/adhkar.source.json, tools/content/duas.source.json

Outputs (deterministic, UTF-8, sorted, indented):
  Packages/IslamicCore/Sources/IslamicCore/Resources/Content/{quran,adhkar,duas}.json

Quran text is copied character for character. Quranic adhkar and duas reference verses
and get their text from the same Tanzil file, so nothing Quranic is typed by hand.

Run: python3 tools/content/build_content.py [--check]
--check fails if the committed JSON differs from what the script would write.
"""
import json
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
    return {"quran.json": quran, "adhkar.json": adhkar, "duas.json": duas}


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
