#!/usr/bin/env python3
"""Checks that build_content.py refuses a bad Hisn correction manifest.

Run: python3 tools/content/test_hisn_corrections.py
Each case edits a copy of tools/content/hisn.corrections.json and expects the build to stop.
"""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("build_content", HERE / "build_content.py")
build_content = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_content)

MANIFEST = json.loads((HERE / "hisn.corrections.json").read_text(encoding="utf-8"))
SURAHS = build_content.load_quran()


def entry(manifest, cid):
    return next(c for c in manifest["corrections"] if c["id"] == cid)


def entry_for(manifest, kind, item):
    return next(c for c in manifest["corrections"] if c["type"] == kind and c.get("sourceItemId") == item)


class HisnCorrectionManifestTests(unittest.TestCase):
    def build(self, manifest):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "hisn.corrections.json"
            path.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
            saved = build_content.HISN_MANIFEST
            build_content.HISN_MANIFEST = path
            try:
                return build_content.build_hisn(SURAHS)
            finally:
                build_content.HISN_MANIFEST = saved

    def rejects(self, edit, message):
        manifest = copy.deepcopy(MANIFEST)
        edit(manifest)
        with self.assertRaises(SystemExit) as raised:
            self.build(manifest)
        self.assertIn(message, str(raised.exception))

    def test_committed_manifest_builds(self):
        hisn = self.build(MANIFEST)
        self.assertEqual(len(hisn["chapters"]), 133)

    def test_nonexistent_item(self):
        def edit(m):
            c = entry_for(m, "BOOK_ITEM_NUMBER", "hisn-001-03")
            c["sourceItemId"] = c["target"]["sourceItemId"] = "hisn-001-99"
        self.rejects(edit, "does not exist")

    def test_nonexistent_chapter(self):
        self.rejects(lambda m: entry_for(m, "PRESENTATION_SECTION", None)["target"].update(chapterId="hisn-ch-200"),
                     "does not exist")

    def test_book_number_out_of_range(self):
        self.rejects(lambda m: entry_for(m, "BOOK_ITEM_NUMBER", "hisn-133-01")["after"].update(bookItemNumber=268),
                     "outside 1...267")

    def test_book_number_from_another_chapter(self):
        self.rejects(lambda m: entry_for(m, "BOOK_ITEM_NUMBER", "hisn-133-01")["after"].update(bookItemNumber=1),
                     "is in book chapter")

    def test_invalid_quran_reference(self):
        def edit(m):
            entry_for(m, "QURAN_CITATION", "hisn-029-03")["after"]["quranCitations"][0]["reference"]["toAyah"] = 287
        self.rejects(edit, "invalid Quran reference")

    def test_missing_evidence(self):
        self.rejects(lambda m: entry_for(m, "REPETITION_COUNT", "hisn-027-20")["evidence"].pop("reason"),
                     "evidence.reason is missing")

    def test_missing_review_status(self):
        self.rejects(lambda m: entry_for(m, "REPETITION_COUNT", "hisn-027-20").pop("reviewStatus"),
                     "missing reviewStatus")

    def test_accepted_without_confidence_or_acceptance(self):
        self.rejects(lambda m: entry_for(m, "REPETITION_COUNT", "hisn-029-06").update(reviewStatus="ACCEPTED"),
                     "LOW confidence")
        self.rejects(lambda m: entry_for(m, "REPETITION_COUNT", "hisn-130-02").update(reviewStatus="ACCEPTED"),
                     "needs acceptedBy")

    def test_conflicting_accepted_corrections(self):
        def edit(m):
            duplicate = copy.deepcopy(entry_for(m, "BOOK_ITEM_NUMBER", "hisn-001-03"))
            duplicate["id"] = "HISN-CORR-999"
            m["corrections"].append(duplicate)
        self.rejects(edit, "conflicts with")

    def test_stale_before_value(self):
        self.rejects(lambda m: entry_for(m, "BOOK_ITEM_NUMBER", "hisn-027-20")["before"].update(bookItemNumber=91),
                     "does not match")

    def test_unmapped_canonical_number(self):
        self.rejects(lambda m: entry_for(m, "BOOK_ITEM_NUMBER", "hisn-029-14").update(reviewStatus="PENDING_DECISION"),
                     "unmapped canonical book items [110]")

    def test_item_without_number_or_relation(self):
        self.rejects(lambda m: entry_for(m, "BOOK_ITEM_NUMBER", "hisn-041-02").update(reviewStatus="PENDING_DECISION"),
                     "has no book item number and no relation")

    def test_contradictory_relation(self):
        def edit(m):
            c = entry_for(m, "BOOK_ITEM_RELATION", "hisn-028-04")
            c["sourceItemId"] = c["target"]["sourceItemId"] = "hisn-027-04"
        self.rejects(edit, "evening variant must be in the evening section")

    def test_undocumented_order_inversion(self):
        def edit(m):
            m["corrections"] = [c for c in m["corrections"]
                                if not (c["type"] == "CANONICAL_ORDER" and "hisn-004-01" in c["target"]["sourceItemIds"])]
        self.rejects(edit, "has no CANONICAL_ORDER entry")

    def test_upstream_hash_change(self):
        self.rejects(lambda m: m["source"].update(upstreamSha256="0" * 64), "upstream hisn.json changed")

    def test_observations_are_never_applied(self):
        self.rejects(lambda m: entry_for(m, "NON_DHIKR_TEXT", "hisn-133-01").update(reviewStatus="ACCEPTED"),
                     "recorded only")
        self.rejects(lambda m: entry_for(m, "TEXT_DISCREPANCY", "hisn-016-01").update(reviewStatus="ACCEPTED"),
                     "ACCEPTED_TEXT_CORRECTION")

    def test_pending_repetition_is_not_applied_until_accepted(self):
        items = {i["id"]: i for ch in self.build(MANIFEST)["chapters"] for i in ch["items"]}
        self.assertIsNone(items["hisn-130-02"]["repetition"]["count"])
        manifest = copy.deepcopy(MANIFEST)
        entry_for(manifest, "REPETITION_COUNT", "hisn-130-02").update(reviewStatus="ACCEPTED", acceptedBy="test")
        items = {i["id"]: i for ch in self.build(manifest)["chapters"] for i in ch["items"]}
        self.assertEqual(items["hisn-130-02"]["repetition"]["count"], 1)


if __name__ == "__main__":
    unittest.main()
