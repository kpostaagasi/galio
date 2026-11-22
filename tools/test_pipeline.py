#!/usr/bin/env python3
"""Unit tests for the data pipeline (run: python3 -m unittest tools/test_pipeline.py)."""
import io
import json
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stderr

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


def _fake_match(queue=420, version="16.23.512.1234", win_team=100, champ_key=3, position="MIDDLE"):
    """A minimal Match-v5 + Timeline pair with one counted participant (pid 1) and filler."""
    parts = []
    for pid in range(1, 11):
        team = 100 if pid <= 5 else 200
        parts.append({
            "participantId": pid, "championId": champ_key if pid == 1 else 999999, "teamId": team,
            "teamPosition": position if pid == 1 else "TOP", "win": team == win_team,
            "summoner1Id": 4, "summoner2Id": 14, "totalMinionsKilled": 210, "neutralMinionsKilled": 15,
            "totalDamageDealtToChampions": 24000, "visionScore": 30, "deaths": 4, "goldEarned": 12000,
            "perks": {"statPerks": {"offense": 5008, "flex": 5008, "defense": 5001},
                      "styles": [{"style": 8000, "selections": [{"perk": 8010}, {"perk": 9111}, {"perk": 9105}, {"perk": 8299}]},
                                 {"style": 8400, "selections": [{"perk": 8473}, {"perk": 8453}]}]},
        })
    match = {"info": {"queueId": queue, "gameVersion": version, "gameDuration": 1800, "participants": parts}}
    ups = [1, 2, 3, 1, 1, 4, 1, 3, 1, 3, 4, 3, 3, 2, 2, 4, 2, 2]
    events = [{"type": "SKILL_LEVEL_UP", "levelUpType": "NORMAL", "participantId": 1, "skillSlot": s} for s in ups]
    events += [{"type": "ITEM_PURCHASED", "participantId": 1, "itemId": i} for i in (3020, 9002, 9001, 9003, 9004)]
    events += [{"type": "ITEM_PURCHASED", "participantId": 1, "itemId": 9005},
               {"type": "ITEM_UNDO", "participantId": 1, "beforeId": 9005, "afterId": 0}]
    return match, {"info": {"frames": [{"events": events}]}}


ITEMS = {3020: {"id": 3020, "boots": True, "legendary": False, "gold": 1100},
         **{i: {"id": i, "boots": False, "legendary": True, "gold": 3000} for i in (9001, 9002, 9003, 9004, 9005)}}
CHAMPS = {3: "Galio"}


class AggregationTests(unittest.TestCase):
    def test_counts_one_match(self):
        counts, seen = aggregate_matches.new_counts("16.23.1"), set()
        m, t = _fake_match()
        self.assertTrue(aggregate_matches.add_match(counts, seen, "TR1_1", m, t, ITEMS, CHAMPS, "tr1"))
        c = counts["champions"]["Galio"]["MIDDLE"]
        self.assertEqual((c["games"], c["wins"]), (1, 1))
        self.assertEqual(c["skillMax"], {"QEW": [1, 1]})
        self.assertEqual(c["skillStart"], {"QWE": [1, 1]})
        self.assertEqual(c["core"], {"9002-9001-9003": [1, 1]})  # undone 9005 is not counted
        self.assertEqual(c["boots"], {"3020": [1, 1]})
        self.assertEqual(c["spells"], {"4-14": [1, 1]})
        self.assertEqual(c["runeTrees"], {"8010:8400": [1, 1]})
        self.assertEqual(counts["byPlatform"], {"tr1": 1})

    def test_dedupe_and_accumulation_across_runs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            data, cache = tmp / "data", tmp / "cache"
            m, t = _fake_match()
            s1 = aggregate_matches.Store("16.23.1", data, cache)
            self.assertTrue(aggregate_matches.add_match(s1.counts, s1.processed, "EUW1_1", m, t, ITEMS, CHAMPS))
            self.assertFalse(aggregate_matches.add_match(s1.counts, s1.processed, "EUW1_1", m, t, ITEMS, CHAMPS))
            s1.save()
            s2 = aggregate_matches.Store("16.23.1", data, cache)  # a later run
            self.assertFalse(aggregate_matches.add_match(s2.counts, s2.processed, "EUW1_1", m, t, ITEMS, CHAMPS))
            self.assertTrue(aggregate_matches.add_match(s2.counts, s2.processed, "EUW1_2", m, t, ITEMS, CHAMPS))
            s2.save()
            s3 = aggregate_matches.Store("16.23.1", data, cache)
            self.assertEqual(s3.counts["matches"], 2)
            self.assertEqual(s3.counts["champions"]["Galio"]["MIDDLE"]["games"], 2)
            self.assertFalse((data / "16.23.1" / "processed_matches.json").exists(), "match IDs stay out of data/")
            published = (data / "16.23.1" / "aggregate_counts.json").read_text()
            self.assertNotIn("EUW1_", published)
            self.assertNotIn("puuid", published.lower())
            s4 = aggregate_matches.Store("16.24.1", data, cache)  # new patch starts empty
            self.assertEqual(s4.counts["matches"], 0)

    def test_rejects_remakes_and_other_queues(self):
        counts, seen = aggregate_matches.new_counts("16.23.1"), set()
        m, t = _fake_match(queue=1700)
        self.assertFalse(aggregate_matches.add_match(counts, seen, "A", m, t, ITEMS, CHAMPS))
        m, t = _fake_match()
        m["info"]["gameDuration"] = 200
        self.assertFalse(aggregate_matches.add_match(counts, seen, "B", m, t, ITEMS, CHAMPS))
        m, t = _fake_match(queue=450)
        self.assertTrue(aggregate_matches.add_match(counts, seen, "C", m, t, ITEMS, CHAMPS))
        self.assertIn("ARAM", counts["champions"]["Galio"])

    def test_thresholds(self):
        counts, seen = aggregate_matches.new_counts("16.23.1"), set()
        for i in range(19):
            m, t = _fake_match(win_team=100 if i % 2 else 200)
            aggregate_matches.add_match(counts, seen, f"M{i}", m, t, ITEMS, CHAMPS)
        for i in range(2):
            m, t = _fake_match(position="TOP")
            aggregate_matches.add_match(counts, seen, f"T{i}", m, t, ITEMS, CHAMPS)
        self.assertEqual(aggregate_matches.derive(counts)["Galio"]["positions"], {}, "19 games is below the threshold")
        m, t = _fake_match()
        aggregate_matches.add_match(counts, seen, "M19", m, t, ITEMS, CHAMPS)
        agg = aggregate_matches.derive(counts)["Galio"]
        self.assertEqual(list(agg["positions"]), ["MIDDLE"], "TOP has under 10 % of the games")
        mid = agg["positions"]["MIDDLE"]
        self.assertEqual(mid["games"], 20)
        self.assertEqual(mid["core"], [9002, 9001, 9003])
        self.assertEqual(mid["runePage"]["perkIds"], [8010, 9111, 9105, 8299, 8473, 8453, 5008, 5008, 5001])
        self.assertEqual(agg["skillMax"], ["Q", "E", "W"])
        self.assertEqual(mid["benchmarks"]["csPerMin"], 7.5)   # 225 CS in 30 min
        self.assertEqual(mid["benchmarks"]["deaths"], 4)
        self.assertNotIn("win", json.dumps(agg).lower(), "no win rates are published")

    def test_rank_prefers_popular_then_smoothed_winrate(self):
        ranked = aggregate_matches._rank({"a": [100, 50], "b": [60, 45], "c": [20, 20]})
        self.assertEqual([k for k, _ in ranked], ["b", "a", "c"])
        self.assertEqual(aggregate_matches._rank({"x": [4, 4]}), [])

    def test_key_loading_and_redaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = pathlib.Path(tmp) / "riot_api_key"
            f.write_text("RGAPI-00000000-1111-2222-3333-444444444444\n")
            self.assertEqual(aggregate_matches.load_key({}, f), "RGAPI-00000000-1111-2222-3333-444444444444")
            self.assertEqual(aggregate_matches.load_key({"RIOT_API_KEY": "RGAPI-env"}, f), "RGAPI-env")
            self.assertEqual(aggregate_matches.load_key({}, pathlib.Path(tmp) / "missing"), "")
        buf = io.StringIO()
        with redirect_stderr(buf):
            aggregate_matches.log("error with RGAPI-00000000-1111-2222-3333-444444444444 in it")
        self.assertNotIn("0000", buf.getvalue())
        self.assertIn("RGAPI-[redacted]", buf.getvalue())

    def test_limiter_reads_headers(self):
        lim = aggregate_matches.HostLimiter()
        lim.configure("100:120,20:1")
        self.assertEqual(lim.windows, [(90, 120.0), (18, 1.0)])


if __name__ == "__main__":
    unittest.main()
