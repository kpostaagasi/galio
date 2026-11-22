#!/usr/bin/env python3
"""Unit tests for the data pipeline (run: python3 -m unittest tools/test_pipeline.py)."""
import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import aggregate_matches  # noqa: E402
import build_data  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent


class PublishedDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = json.loads((ROOT / "data" / "manifest.json").read_text())
        cls.manifest = manifest
        cls.data = json.loads((ROOT / "data" / manifest["latest"] / "all.json").read_text())

    def test_manifest_points_to_existing_bundle(self):
        self.assertEqual(self.manifest["schema"], 1)
        self.assertTrue((ROOT / "data" / self.manifest["files"]["all"]).exists())
        bundled = json.loads((ROOT / "Galio" / "Resources" / "BundledData" / "manifest.json").read_text())
        self.assertEqual(bundled["latest"], self.manifest["latest"], "bundled data must match the published patch")

    def test_every_rune_page_is_valid(self):
        ridx = build_data.rune_index(self.data["runes"])
        for cid, d in self.data["details"].items():
            for key, b in d["builds"].items():
                for page in b["runes"]:
                    self.assertTrue(build_data.valid_page(page, ridx), f"{cid} {key} {page}")

    def test_per_champion_files_exist(self):
        patch = self.manifest["latest"]
        for c in self.data["champions"]:
            self.assertTrue((ROOT / "data" / patch / "champions" / f"{c['id']}.json").exists(), c["id"])

    def test_items_have_flags_for_key_counters(self):
        items = {i["name"]: i for i in sorted(self.data["items"], key=lambda i: -i["id"])}  # base SR ids win
        self.assertIn("antiheal", items["Thornmail"]["flags"])
        self.assertIn("antiheal", items["Mortal Reminder"]["flags"])
        self.assertIn("anticrit", items["Randuin's Omen"]["flags"])
        self.assertIn("stasis", items["Zhonya's Hourglass"]["flags"])
        self.assertIn("mpen", items["Void Staff"]["flags"])

    def test_no_win_rates_in_augments(self):
        for fam, augs in self.data["augments"].items():
            for a in augs:
                self.assertNotIn("winRate", a)
                self.assertNotIn("winrate", json.dumps(a).lower())


class PipelineUnitTests(unittest.TestCase):
    def test_skill_max_order_from_levelups(self):
        # Q W E Q Q R Q E Q E R E E W W R W W
        seq = [1, 2, 3, 1, 1, 4, 1, 3, 1, 3, 4, 3, 3, 2, 2, 4, 2, 2]
        self.assertEqual(aggregate_matches.skill_max_order(seq), ["Q", "E", "W"])
        self.assertIsNone(aggregate_matches.skill_max_order([]))

    def test_strip_tags(self):
        self.assertEqual(build_data.strip_tags("<b>Hi</b><br>there"), "Hi there")

    def test_curated_table_parses(self):
        table = build_data.load_curated_champions()
        self.assertGreater(len(table), 160)
        self.assertEqual(table["Galio"]["archetype"], "tankmage")
        self.assertEqual(table["Ashe"]["archetypes"].get("UTILITY"), "artillery")


if __name__ == "__main__":
    unittest.main()
