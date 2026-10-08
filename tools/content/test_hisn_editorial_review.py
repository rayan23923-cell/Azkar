#!/usr/bin/env python3
"""Phase 2F: checks the Hisn editorial review gate.

Run: python3 tools/content/test_hisn_editorial_review.py

The first group checks the committed decisions and the generated hisn.json; the second edits a
copy of tools/content/hisn.editorial_review.json and expects build_content.py to stop.
"""
import copy
import hashlib
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location("build_content", HERE / "build_content.py")
build_content = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_content)

REVIEW = json.loads((HERE / "hisn.editorial_review.json").read_text(encoding="utf-8"))
MANIFEST = json.loads((HERE / "hisn.corrections.json").read_text(encoding="utf-8"))
RECONCILIATION = json.loads((HERE / "hisn.reconciliation.json").read_text(encoding="utf-8"))
UPSTREAM_FILE = ROOT / "Packages/IslamicCore/Upstream/hisn/asellam/hisn.json"
BUNDLED = json.loads((ROOT / "Packages/IslamicCore/Sources/IslamicCore/Resources/Content/hisn.json").read_text(encoding="utf-8"))
QURAN = json.loads((ROOT / "Packages/IslamicCore/Sources/IslamicCore/Resources/Content/quran.json").read_text(encoding="utf-8"))
UPSTREAM_SHA256 = "b30a448ef40184b0422c40bd3c372bf2b25bfb5b0539fd3699e6b4fba9459d80"
SURAHS = build_content.load_quran()

# The fifteen P0 findings Phase 2E left open, in the order of the Phase 2F request.
P0_ITEMS = {
    "TEXT_DISCREPANCY": ["hisn-016-01", "hisn-016-06", "hisn-017-04", "hisn-025-02", "hisn-029-15",
                         "hisn-037-02", "hisn-043-01", "hisn-052-02", "hisn-112-01"],
    "NON_DHIKR_TEXT": ["hisn-001-03", "hisn-133-01", "hisn-029-14"],
    "REPETITION_COUNT": ["hisn-130-02", "hisn-130-06", "hisn-029-06"],
}
MARKS = re.compile(r"[ً-ْ]")


def items(book=BUNDLED):
    return {i["id"]: i for ch in book["chapters"] for i in ch["items"]}


def review_for(manifest, item):
    return next(r for r in manifest["reviews"] if r["sourceItemId"] == item)


class CommittedDecisionTests(unittest.TestCase):
    def test_all_fifteen_p0_findings_are_reviewed_once(self):
        expected = [(issue, item) for issue, ids in P0_ITEMS.items() for item in ids]
        self.assertEqual([(r["issueType"], r["sourceItemId"]) for r in REVIEW["reviews"]], expected)
        self.assertEqual([r["id"] for r in REVIEW["reviews"]], [f"HISN-REVIEW-{n:03d}" for n in range(1, 16)])

    def test_every_decision_has_evidence(self):
        for r in REVIEW["reviews"]:
            self.assertIn(r["decision"], build_content.EDITORIAL_DECISIONS, r["id"])
            self.assertTrue(r["evidence"], r["id"])
            for ev in r["evidence"]:
                for key in ("source", "reference", "finding"):
                    self.assertTrue(ev.get(key, "").strip(), f"{r['id']} evidence.{key}")
            self.assertGreater(len(r["rationale"]), 30, r["id"])

    def test_texts_in_the_review_are_verbatim(self):
        bundled = items()
        books = {b["bookItemNumber"]: b for b in RECONCILIATION["bookItems"]}
        for r in REVIEW["reviews"]:
            item = bundled[r["sourceItemId"]]
            self.assertEqual(r["sourceText"], item["arabicText"], r["id"])
            self.assertEqual(r["bookText"], books[item["bookItemNumber"]]["bookText"], r["id"])
            # Every vowelled quotation of the source is an exact span of it.
            for ev in r["evidence"]:
                if ev["source"].startswith("Tier 3"):
                    for quote in re.findall(r"«([^»]+)»", ev["finding"]):
                        if MARKS.search(quote):
                            self.assertIn(quote.rstrip(" …"), item["arabicText"], r["id"])

    def test_no_fabricated_independent_review(self):
        self.assertFalse(REVIEW["editorialReviewComplete"])
        self.assertIsNone(REVIEW["independentReview"]["reviewer"])
        for r in REVIEW["reviews"]:
            self.assertIsNone(r["independentReviewer"], r["id"])
            self.assertEqual(r["reviewStatus"], "EDITORIAL_DECISION_RECORDED", r["id"])
        for item in items().values():
            self.assertEqual(item["reviewStatus"], "CONTENT_REVIEW_REQUIRED", item["id"])
            self.assertEqual(item["repetition"]["reviewStatus"], "CONTENT_REVIEW_REQUIRED", item["id"])
        self.assertEqual(BUNDLED["book"]["provenance"]["editorialReview"]["independentlyReviewed"], 0)

    def test_no_text_change_without_accepted_text_correction(self):
        text_corrections = [c for c in MANIFEST["corrections"] if c["reviewStatus"] == "ACCEPTED_TEXT_CORRECTION"]
        for c in text_corrections:
            self.assertTrue(c["before"]["arabicText"] and c["after"]["arabicText"] and c.get("acceptedBy"), c["id"])
        changed = {c["sourceItemId"] for c in text_corrections}
        upstream = json.loads(UPSTREAM_FILE.read_text(encoding="utf-8"))
        for chapter in BUNDLED["chapters"]:
            source = upstream[chapter["titleArabic"]]["Adhkar"]
            for item, raw in zip(chapter["items"], source):
                if item["id"] not in changed:
                    self.assertEqual(item["arabicText"], raw["Text"], item["id"])
        self.assertEqual(sum(r["changesApplied"] for r in REVIEW["reviews"]), len(text_corrections))

    def test_upstream_is_unchanged(self):
        self.assertEqual(hashlib.sha256(UPSTREAM_FILE.read_bytes()).hexdigest(), UPSTREAM_SHA256)
        self.assertEqual(REVIEW["source"]["upstreamSha256"], UPSTREAM_SHA256)

    def test_repetition_counts_are_whole_item_counts(self):
        bundled = items()
        for item_id in P0_ITEMS["REPETITION_COUNT"]:
            self.assertEqual(review_for(REVIEW, item_id)["decision"], "KEEP_NIL")
            self.assertIsNone(bundled[item_id]["repetition"]["count"], item_id)
        # A structured count is the source's own count unless an accepted entry set it.
        accepted = {c["sourceItemId"]: c["after"]["count"] for c in MANIFEST["corrections"]
                    if c["type"] == "REPETITION_COUNT" and c["reviewStatus"] == "ACCEPTED"}
        for item in bundled.values():
            count = item["repetition"]["count"]
            if item["id"] in accepted:
                self.assertEqual(count, accepted[item["id"]], item["id"])
            elif count is not None:
                self.assertEqual(count, item["repetition"]["sourceCount"], item["id"])
        self.assertEqual(bundled["hisn-025-02"]["repetition"]["count"], None, "[ثلاثاً] is not a whole-item count")
        self.assertEqual(bundled["hisn-043-01"]["repetition"]["count"], 3)

    def test_quran_citations_remain_valid(self):
        ayahs = {s["id"]: s["ayahCount"] for s in QURAN["surahs"]}
        for item in items().values():
            for cit in item["quranCitations"]:
                ref = cit["reference"]
                self.assertTrue(1 <= ref["fromAyah"] <= ref["toAyah"] <= ayahs[ref["surah"]], item["id"])
                if cit["recitesWholeSurah"]:
                    self.assertEqual(ref["fromAyah"], 1, item["id"])
        surahs = items()["hisn-029-14"]["quranCitations"]
        self.assertEqual([(c["reference"]["surah"], c["recitesWholeSurah"]) for c in surahs], [(32, True), (67, True)])

    def test_non_recitation_text_is_metadata_over_verbatim_spans(self):
        bundled = items()
        roles = {"hisn-001-03": ["NARRATION"], "hisn-133-01": ["CLOSING"], "hisn-029-14": ["LABEL", "LABEL"]}
        for item in bundled.values():
            self.assertEqual([p["role"] for p in item["nonRecitationText"]], roles.get(item["id"], []), item["id"])
            for piece in item["nonRecitationText"]:
                self.assertEqual(item["arabicText"].count(piece["text"]), 1, item["id"])

    def test_rights_unchanged(self):
        self.assertEqual(BUNDLED["book"]["attribution"]["rightsStatus"], "PENDING_PRE_RELEASE_REVIEW")
        self.assertIsNone(BUNDLED["book"]["attribution"]["attributionText"])

    def test_p1_findings_untouched(self):
        p1 = [c for c in MANIFEST["corrections"] if c["reviewPriority"] == "P1"]
        statuses = {}
        for c in p1:
            statuses[(c["type"], c["reviewStatus"])] = statuses.get((c["type"], c["reviewStatus"]), 0) + 1
        self.assertEqual(statuses, {
            ("BOOK_ITEM_NUMBER", "PENDING_DECISION"): 1,
            ("PRESENTATION_SECTION", "ACCEPTED"): 2,
            ("BOOK_ITEM_RELATION", "ACCEPTED"): 8,
            ("BOOK_ITEM_RELATION", "OBSERVATION"): 8,
            ("REFERENCE_METADATA", "OBSERVED_DIFFERENCE"): 22,
            ("REFERENCE_METADATA", "OBSERVATION"): 1,
        })
        upstream = json.loads(UPSTREAM_FILE.read_text(encoding="utf-8"))
        for chapter in BUNDLED["chapters"]:
            for item, raw in zip(chapter["items"], upstream[chapter["titleArabic"]]["Adhkar"]):
                self.assertEqual(item["references"][0]["originalText"] if item["references"] else "",
                                 raw["Reference"].strip(), item["id"])

    def test_canonical_structure_is_unchanged(self):
        summary = BUNDLED["book"]["provenance"]["corrections"]
        self.assertEqual((summary["canonicalBookChapters"], summary["canonicalBookItems"],
                          summary["presentationSections"], summary["displayItems"]), (132, 267, 133, 302))
        numbers = {i["bookItemNumber"] for i in items().values()} - {None}
        self.assertEqual(numbers, set(range(1, 268)))
        self.assertEqual(len({c["bookChapterNumber"] for c in BUNDLED["chapters"]}), 132)


class EditorialReviewRejectionTests(unittest.TestCase):
    def build(self, review=REVIEW, manifest=MANIFEST):
        with tempfile.TemporaryDirectory() as tmp:
            rpath, mpath = Path(tmp) / "review.json", Path(tmp) / "manifest.json"
            rpath.write_text(json.dumps(review, ensure_ascii=False), encoding="utf-8")
            mpath.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
            saved = build_content.HISN_EDITORIAL_REVIEW, build_content.HISN_MANIFEST
            build_content.HISN_EDITORIAL_REVIEW, build_content.HISN_MANIFEST = rpath, mpath
            try:
                return build_content.build_hisn(SURAHS)
            finally:
                build_content.HISN_EDITORIAL_REVIEW, build_content.HISN_MANIFEST = saved

    def rejects(self, edit, message, edit_manifest=None):
        review, manifest = copy.deepcopy(REVIEW), copy.deepcopy(MANIFEST)
        edit(review)
        if edit_manifest:
            edit_manifest(manifest)
        with self.assertRaises(SystemExit) as raised:
            self.build(review, manifest)
        self.assertIn(message, str(raised.exception))

    def test_committed_review_builds(self):
        self.assertEqual(self.build()["book"]["provenance"]["editorialReview"]["total"], 15)

    def test_missing_review_leaves_a_p0_open(self):
        self.rejects(lambda r: r["reviews"].pop(5), "P0 entries without a decision")

    def test_missing_or_unknown_decision(self):
        self.rejects(lambda r: r["reviews"][0].pop("decision"), "missing decision")
        self.rejects(lambda r: r["reviews"][0].update(decision="LOOKS_RIGHT"), "unknown decision")

    def test_evidence_is_required(self):
        self.rejects(lambda r: r["reviews"][0].update(evidence=[]), "needs evidence")
        self.rejects(lambda r: r["reviews"][0]["evidence"][0].pop("finding"), "evidence.finding is missing")

    def test_fabricated_reviewer(self):
        self.rejects(lambda r: r["reviews"][0].update(independentReviewer="verified"), "independentReviewer must be null")
        self.rejects(lambda r: r["reviews"][0].update(reviewStatus="INDEPENDENTLY_REVIEWED"), "must match the independent reviewer")
        self.rejects(lambda r: r.update(editorialReviewComplete=True), "editorialReviewComplete needs")

    def test_defer_changes_nothing(self):
        self.rejects(lambda r: review_for(r, "hisn-037-02").update(changesApplied=True), "DEFER applies no change")

    def test_accepted_correction_needs_the_text_mechanism(self):
        self.rejects(lambda r: review_for(r, "hisn-037-02").update(decision="ACCEPT_CORRECTION", changesApplied=True),
                     "needs an ACCEPTED_TEXT_CORRECTION")

    def test_text_mechanism_needs_acceptance(self):
        def manifest(m):
            c = next(c for c in m["corrections"] if c["id"] == "HISN-CORR-053")
            c.update(reviewStatus="ACCEPTED_TEXT_CORRECTION", after={"arabicText": c["before"]["arabicText"]})
        self.rejects(lambda r: None, "needs acceptedBy", manifest)

    def test_metadata_span_must_be_verbatim(self):
        self.rejects(lambda r: review_for(r, "hisn-133-01")["metadata"][0].update(text="وصلى الله على محمد"),
                     "exactly once, verbatim")

    def test_keep_nil_needs_a_nil_count(self):
        self.rejects(lambda r: review_for(r, "hisn-043-01").update(decision="KEEP_NIL"), "KEEP_NIL is for repetition")

    def test_review_must_quote_the_item(self):
        self.rejects(lambda r: review_for(r, "hisn-112-01").update(sourceText="نص آخر"), "sourceText is not the item's text")

    def test_accepted_text_correction_flows_through_the_existing_mechanism(self):
        # Identity replacement: exercises the mechanism without writing any new religious text.
        review, manifest = copy.deepcopy(REVIEW), copy.deepcopy(MANIFEST)
        c = next(c for c in manifest["corrections"] if c["id"] == "HISN-CORR-053")
        c.update(reviewStatus="ACCEPTED_TEXT_CORRECTION", acceptedBy="test",
                 after={"arabicText": c["before"]["arabicText"]})
        review_for(review, "hisn-037-02").update(decision="ACCEPT_CORRECTION", changesApplied=True)
        item = items(self.build(review, manifest))["hisn-037-02"]
        self.assertIn("HISN-CORR-053", item["corrections"]["applied"])
        self.assertEqual(item["editorialReviews"][0]["changesApplied"], True)


if __name__ == "__main__":
    unittest.main()
