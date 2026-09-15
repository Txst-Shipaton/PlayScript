import unittest
from create_narration import word_cues, speaker_segments, ROOT
import json


class AlignmentTests(unittest.TestCase):
    def test_cast_assigns_mixed_dialogue_without_changing_text(self):
        story = json.loads((ROOT / "StoryCore/Sources/StoryCore/Resources/romeo-and-juliet.json").read_text())
        reunion = next(beat for beat in story["beats"] if beat["id"] == "in-time")
        parts = speaker_segments(reunion["id"], reunion["text"])
        self.assertEqual([speaker for speaker, _ in parts], ["Narrator", "Juliet", "Romeo", "Narrator", "Romeo"])
        self.assertEqual("".join(text for _, text in parts), reunion["text"])
        self.assertTrue(all(text.strip() for _, text in parts))

    def test_bundled_cast_audio_and_cues_are_complete(self):
        story = json.loads((ROOT / "StoryCore/Sources/StoryCore/Resources/romeo-and-juliet.json").read_text())
        voices = {}
        for beat in story["beats"]:
            pages = [(beat["id"], beat["text"])] + [(beat["id"] + "--" + c["id"], c["flavor"]) for c in beat["choices"]]
            for page_id, text in pages:
                folder = ROOT / "PlayScript/Resources/Narration"
                playlist = json.loads((folder / f"cast-{page_id}.json").read_text())
                self.assertEqual(playlist["text"], text)
                self.assertEqual([(s["speaker"], s["text"]) for s in playlist["segments"]], speaker_segments(page_id, text))
                for part in playlist["segments"]:
                    self.assertTrue((folder / (part["resource"] + ".mp3")).stat().st_size > 500)
                    self.assertEqual("".join(c["text"] for c in part["cues"]), part["text"])
                    metadata = json.loads((folder / (part["resource"] + ".json")).read_text())
                    voices.setdefault(part["speaker"], set()).add(metadata["voiceID"])
        self.assertEqual(set(voices), {"Narrator", "Romeo", "Juliet"})
        self.assertEqual(len(set.union(*voices.values())), 3)

    def alignment(self, text):
        return {"characters": list(text),
                "character_start_times_seconds": [i * 0.1 for i in range(len(text))],
                "character_end_times_seconds": [(i + 1) * 0.1 for i in range(len(text))]}

    def test_preserves_paragraphs_and_punctuation(self):
        text = "Romeo.\n\nHere—with me?"
        cues = word_cues(text, self.alignment(text))
        self.assertEqual("".join(c["text"] for c in cues), text)
        self.assertAlmostEqual(cues[0]["end"], 0.6)
        self.assertAlmostEqual(cues[1]["start"], 0.8)

    def test_rejects_normalized_or_missing_alignment(self):
        with self.assertRaises(ValueError):
            word_cues("Forty-two hours", self.alignment("42 hours"))
        with self.assertRaises(ValueError):
            word_cues("Hello", None)

    def test_rejects_backwards_timing(self):
        alignment = self.alignment("One two")
        alignment["character_start_times_seconds"][4] = -1
        with self.assertRaises(ValueError):
            word_cues("One two", alignment)


if __name__ == "__main__":
    unittest.main()
