import unittest
from create_narration import word_cues


class AlignmentTests(unittest.TestCase):
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
