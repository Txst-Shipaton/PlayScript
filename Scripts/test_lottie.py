#!/usr/bin/env python3
"""Structural checks for the authored Lottie files.

A malformed Lottie animation fails silently at runtime -- it simply does not
play -- so these assertions stand in for the rendering that cannot happen on a
machine without Xcode. They verify the schema lottie-ios relies on, and the
seamless-loop property each animation is built to have.
"""
import json
from pathlib import Path
import unittest

import create_lottie

TRANSFORM_KEYS = {"o", "r", "p", "a", "s"}


class LottieStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.animations = {
            "scene-orchard": create_lottie.orchard(),
            "scene-chamber": create_lottie.chamber(),
            "scene-tomb": create_lottie.tomb(),
            "scene-road": create_lottie.road(),
            "accent-letter": create_lottie.letter(),
            "accent-thought": create_lottie.thought(),
        }

    def properties(self, animation):
        for layer in animation["layers"]:
            for name, value in layer["ks"].items():
                yield layer, name, value

    def test_composition_header(self):
        for name, animation in self.animations.items():
            with self.subTest(name):
                for key in ("v", "fr", "ip", "op", "w", "h", "layers", "assets"):
                    self.assertIn(key, animation)
                self.assertGreater(animation["op"], animation["ip"])
                self.assertEqual(animation["fr"], create_lottie.FR)
                self.assertTrue(animation["layers"], "an empty composition renders nothing")

    def test_layers_are_complete(self):
        for name, animation in self.animations.items():
            with self.subTest(name):
                indexes = [layer["ind"] for layer in animation["layers"]]
                self.assertEqual(len(indexes), len(set(indexes)), "duplicate layer index")
                for layer in animation["layers"]:
                    self.assertEqual(layer["ty"], 4)
                    self.assertEqual(set(layer["ks"]), TRANSFORM_KEYS)
                    self.assertTrue(layer["shapes"])
                    self.assertLessEqual(layer["op"], animation["op"])

    def test_shape_groups_carry_a_transform(self):
        """lottie-ios drops a group that has no trailing transform item."""
        for name, animation in self.animations.items():
            with self.subTest(name):
                for layer in animation["layers"]:
                    for shape in layer["shapes"]:
                        self.assertEqual(shape["ty"], "gr")
                        self.assertEqual(shape["it"][-1]["ty"], "tr")
                        kinds = {item["ty"] for item in shape["it"]}
                        self.assertTrue(kinds & {"fl", "st"}, "a shape with no fill or stroke")

    def test_keyframe_times_are_monotonic_and_in_range(self):
        for name, animation in self.animations.items():
            for layer, prop, value in self.properties(animation):
                if value["a"] != 1:
                    continue
                with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                    times = [frame["t"] for frame in value["k"]]
                    self.assertEqual(times, sorted(times))
                    self.assertEqual(len(times), len(set(times)))
                    self.assertGreaterEqual(times[0], animation["ip"])
                    self.assertLessEqual(times[-1], animation["op"])

    def test_every_animated_property_loops_seamlessly(self):
        """First and last keyframe must match, or the loop visibly jumps."""
        for name, animation in self.animations.items():
            for layer, prop, value in self.properties(animation):
                if value["a"] != 1 or len(value["k"]) < 2:
                    continue
                with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                    first, last = value["k"][0]["s"], value["k"][-1]["s"]
                    self.assertEqual(value["k"][-1]["t"], animation["op"],
                                     "animation does not run to the composition end")
                    if prop == "r":
                        continue  # Rotation is allowed to accumulate a full turn.
                    if isinstance(first[0], dict):
                        self.assertEqual(first[0]["v"], last[0]["v"])
                    else:
                        for a, b in zip(first, last):
                            self.assertAlmostEqual(a, b, places=6)

    def test_interpolation_handles_are_sized_to_the_value(self):
        for name, animation in self.animations.items():
            for layer, prop, value in self.properties(animation):
                if value["a"] != 1:
                    continue
                with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                    for frame in value["k"][:-1]:
                        self.assertEqual(len(frame["i"]["x"]), len(frame["s"]))
                        self.assertEqual(len(frame["o"]["y"]), len(frame["s"]))

    def test_paths_keep_a_constant_vertex_count(self):
        """Morphing between different vertex counts is undefined behaviour."""
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for shape in layer["shapes"]:
                    for item in shape["it"]:
                        if item["ty"] != "sh" or item["ks"]["a"] != 1:
                            continue
                        with self.subTest(f"{name}/{layer['nm']}"):
                            counts = {len(frame["s"][0]["v"]) for frame in item["ks"]["k"]}
                            self.assertEqual(len(counts), 1)
                            for frame in item["ks"]["k"]:
                                shape_value = frame["s"][0]
                                self.assertEqual(len(shape_value["i"]), len(shape_value["v"]))
                                self.assertEqual(len(shape_value["o"]), len(shape_value["v"]))

    def test_colors_and_opacity_stay_in_range(self):
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for shape in layer["shapes"]:
                    for item in shape["it"]:
                        if item["ty"] in ("fl", "st"):
                            with self.subTest(f"{name}/{layer['nm']}"):
                                for channel in item["c"]["k"]:
                                    self.assertGreaterEqual(channel, 0)
                                    self.assertLessEqual(channel, 1)
                for _, prop, value in [(0, k, v) for k, v in layer["ks"].items()]:
                    if prop != "o":
                        continue
                    values = ([frame["s"][0] for frame in value["k"]]
                              if value["a"] == 1 else [value["k"]])
                    for opacity in values:
                        self.assertGreaterEqual(opacity, 0)
                        self.assertLessEqual(opacity, 100)

    def test_written_files_match_the_generator(self):
        for name, animation in self.animations.items():
            path = create_lottie.OUTPUT / (name + ".json")
            with self.subTest(name):
                self.assertTrue(path.exists(), "run Scripts/create_lottie.py")
                self.assertEqual(json.loads(path.read_text()), json.loads(json.dumps(animation)))


if __name__ == "__main__":
    unittest.main()
