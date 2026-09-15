#!/usr/bin/env python3
"""Structural checks for the authored Lottie files.

A malformed Lottie animation fails silently at runtime -- it simply does not
play -- so these assertions stand in for the rendering that cannot happen on a
machine without Xcode. They verify the schema lottie-ios relies on, the
constraints its Core Animation rendering engine imposes, and the seamless-loop
property every animation is built to have.
"""
import json
from pathlib import Path
import unittest

import create_lottie

TRANSFORM_KEYS = {"o", "r", "p", "a", "s"}
PATH_ITEMS = {"sh", "el", "rc", "sr"}
PAINT_ITEMS = {"fl", "st", "gf", "gs"}
# A single file over this is a sign that keyframe sampling has run away.
MAX_FILE_KB = 700
MAX_TOTAL_KB = 3 * 1024


def animated_properties(node, path=""):
    """Every animated property anywhere in a layer, including inside shapes."""
    if isinstance(node, dict):
        if node.get("a") == 1 and isinstance(node.get("k"), list):
            yield path, node
            return
        for key, value in node.items():
            yield from animated_properties(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from animated_properties(value, f"{path}[{index}]")


def shape_items(layer):
    for shape in layer["shapes"]:
        for item in shape["it"]:
            yield shape, item


def opacity_at(layer, index):
    """The layer's opacity at the first (0) or last (-1) keyframe."""
    opacity = layer["ks"]["o"]
    if opacity["a"] != 1:
        return opacity["k"]
    return opacity["k"][index]["s"][0]


class LottieStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.animations = {name: builder()
                          for name, builder in create_lottie.ANIMATIONS.items()}

    def layer_properties_of(self, layer):
        for name, value in layer["ks"].items():
            if value.get("a") == 1:
                yield f"ks.{name}", value
        yield from animated_properties(layer["shapes"], "shapes")

    # -- composition ------------------------------------------------------

    def test_composition_header(self):
        for name, animation in self.animations.items():
            with self.subTest(name):
                for key in ("v", "fr", "ip", "op", "w", "h", "layers", "assets"):
                    self.assertIn(key, animation)
                self.assertGreater(animation["op"], animation["ip"])
                self.assertEqual(animation["fr"], create_lottie.FR)
                self.assertGreater(animation["w"], 0)
                self.assertGreater(animation["h"], 0)
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

    def test_layer_windows_sit_inside_the_composition(self):
        """A layer that crosses once lives in its own window, not the whole loop."""
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                with self.subTest(f"{name}/{layer['nm']}"):
                    self.assertGreaterEqual(layer["ip"], animation["ip"])
                    self.assertLessEqual(layer["op"], animation["op"])
                    self.assertLess(layer["ip"], layer["op"])

    # -- shapes -----------------------------------------------------------

    def test_shape_groups_carry_a_transform(self):
        """lottie-ios drops a group that has no trailing transform item."""
        for name, animation in self.animations.items():
            with self.subTest(name):
                for layer in animation["layers"]:
                    for shape in layer["shapes"]:
                        self.assertEqual(shape["ty"], "gr")
                        self.assertEqual(shape["it"][-1]["ty"], "tr")
                        kinds = {item["ty"] for item in shape["it"]}
                        self.assertTrue(kinds & PAINT_ITEMS, "a shape with no fill or stroke")

    def test_each_group_draws_exactly_one_path(self):
        """The Core Animation engine bails out of a group with two path items."""
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for shape in layer["shapes"]:
                    with self.subTest(f"{name}/{layer['nm']}/{shape['nm']}"):
                        drawn = [item for item in shape["it"] if item["ty"] in PATH_ITEMS]
                        self.assertEqual(len(drawn), 1)

    def test_paths_keep_a_constant_vertex_count(self):
        """Morphing between different vertex counts is undefined behaviour."""
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for _, item in shape_items(layer):
                    if item["ty"] != "sh":
                        continue
                    with self.subTest(f"{name}/{layer['nm']}"):
                        values = ([frame["s"][0] for frame in item["ks"]["k"]]
                                  if item["ks"]["a"] == 1 else [item["ks"]["k"]])
                        self.assertEqual(len({len(value["v"]) for value in values}), 1)
                        for value in values:
                            self.assertEqual(len(value["i"]), len(value["v"]))
                            self.assertEqual(len(value["o"]), len(value["v"]))
                            self.assertIn(value["c"], (True, False))

    def test_vector_properties_carry_both_components(self):
        """lottie-ios reads a vector as [x, y, z] and fills missing slots with 0.

        A one-element scale therefore decodes as a y of zero and the layer
        collapses to an invisible line -- a silent failure with no error.
        """
        def check(label, prop):
            values = ([frame["s"] for frame in prop["k"]] if prop["a"] == 1
                      else [prop["k"]])
            for value in values:
                with self.subTest(label):
                    self.assertIsInstance(value, list)
                    self.assertGreaterEqual(len(value), 2)

        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for key in ("p", "a", "s"):
                    check(f"{name}/{layer['nm']}/ks.{key}", layer["ks"][key])
                for _, item in shape_items(layer):
                    for key in ("s", "e", "p"):
                        if item["ty"] in ("el", "rc") and key in ("s", "p"):
                            check(f"{name}/{layer['nm']}/{item['ty']}.{key}", item[key])
                        elif item["ty"] in ("gf", "gs") and key in ("s", "e"):
                            check(f"{name}/{layer['nm']}/{item['ty']}.{key}", item[key])
                    if item["ty"] == "tr":
                        for key in ("p", "a", "s"):
                            check(f"{name}/{layer['nm']}/tr.{key}", item[key])

    def test_sizes_are_positive(self):
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for _, item in shape_items(layer):
                    if item["ty"] not in ("el", "rc"):
                        continue
                    with self.subTest(f"{name}/{layer['nm']}"):
                        sizes = ([frame["s"] for frame in item["s"]["k"]]
                                 if item["s"]["a"] == 1 else [item["s"]["k"]])
                        for size in sizes:
                            self.assertEqual(len(size), 2)
                            self.assertTrue(all(value > 0 for value in size))

    # -- paint ------------------------------------------------------------

    def test_colors_and_opacity_stay_in_range(self):
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for _, item in shape_items(layer):
                    if item["ty"] in ("fl", "st"):
                        with self.subTest(f"{name}/{layer['nm']}"):
                            for channel in item["c"]["k"]:
                                self.assertGreaterEqual(channel, 0)
                                self.assertLessEqual(channel, 1)
                    if item["ty"] in PAINT_ITEMS:
                        with self.subTest(f"{name}/{layer['nm']}/paint-opacity"):
                            values = ([frame["s"][0] for frame in item["o"]["k"]]
                                      if item["o"]["a"] == 1 else [item["o"]["k"]])
                            for value in values:
                                self.assertGreaterEqual(value, 0)
                                self.assertLessEqual(value, 100)
                for name_, value in layer["ks"].items():
                    if name_ != "o":
                        continue
                    values = ([frame["s"][0] for frame in value["k"]]
                              if value["a"] == 1 else [value["k"]])
                    for opacity in values:
                        self.assertGreaterEqual(opacity, 0)
                        self.assertLessEqual(opacity, 100)

    def test_gradients_are_well_formed(self):
        """A gradient with a malformed ramp renders as nothing at all.

        Bodymovin packs the ramp as `p` repetitions of [location, r, g, b],
        optionally followed by repetitions of [location, alpha]. lottie-ios
        reads the colour block by index, so a miscounted array is fatal.
        """
        found = 0
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for _, item in shape_items(layer):
                    if item["ty"] not in ("gf", "gs"):
                        continue
                    found += 1
                    with self.subTest(f"{name}/{layer['nm']}"):
                        for key in ("s", "e", "t", "g", "o"):
                            self.assertIn(key, item)
                        self.assertIn(item["t"], (1, 2), "gradient type must be linear or radial")
                        self.assertEqual(item["s"]["a"], 0)
                        self.assertEqual(item["e"]["a"], 0)
                        self.assertEqual(len(item["s"]["k"]), 2)
                        self.assertEqual(len(item["e"]["k"]), 2)
                        self.assertNotEqual(item["s"]["k"], item["e"]["k"],
                                            "a zero-length gradient has no direction")
                        stops = item["g"]["p"]
                        self.assertGreaterEqual(stops, 2)
                        ramp = item["g"]["k"]["k"]
                        self.assertEqual(item["g"]["k"]["a"], 0)
                        self.assertGreaterEqual(len(ramp), stops * 4)
                        remainder = len(ramp) - stops * 4
                        self.assertEqual(remainder % 2, 0,
                                         "alpha stops come in [location, alpha] pairs")
                        colours = ramp[:stops * 4]
                        locations = colours[0::4]
                        self.assertEqual(locations, sorted(locations))
                        self.assertAlmostEqual(locations[0], 0.0)
                        self.assertAlmostEqual(locations[-1], 1.0)
                        for index in range(stops):
                            for channel in colours[index * 4 + 1:index * 4 + 4]:
                                self.assertGreaterEqual(channel, 0)
                                self.assertLessEqual(channel, 1)
                        alphas = ramp[stops * 4:]
                        alpha_locations = alphas[0::2]
                        self.assertEqual(alpha_locations, sorted(alpha_locations))
                        for value in alphas[1::2]:
                            self.assertGreaterEqual(value, 0)
                            self.assertLessEqual(value, 1)
        self.assertGreater(found, 0, "the gradient checks are not reaching anything")

    def test_trim_paths_are_well_formed(self):
        """Trim start must never exceed trim end, or lottie-ios draws nothing."""
        found = 0
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for shape, item in shape_items(layer):
                    if item["ty"] != "tm":
                        continue
                    found += 1
                    with self.subTest(f"{name}/{layer['nm']}/{shape['nm']}"):
                        self.assertIn(item["m"], (1, 2))
                        bounds = {}
                        for key in ("s", "e", "o"):
                            self.assertIn(key, item)
                            values = ([frame["s"][0] for frame in item[key]["k"]]
                                      if item[key]["a"] == 1 else [item[key]["k"]])
                            bounds[key] = values
                            if key != "o":
                                for value in values:
                                    self.assertGreaterEqual(value, 0)
                                    self.assertLessEqual(value, 100)
                        self.assertLessEqual(max(bounds["s"]), min(bounds["e"]),
                                             "trim start crosses trim end")
        self.assertGreater(found, 0, "the trim checks are not reaching anything")

    # -- keyframes --------------------------------------------------------

    def test_keyframe_times_span_the_layer_window(self):
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for prop, value in self.layer_properties_of(layer):
                    with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                        times = [frame["t"] for frame in value["k"]]
                        self.assertEqual(times, sorted(times))
                        self.assertEqual(len(times), len(set(times)))
                        self.assertEqual(times[0], layer["ip"],
                                         "a property that starts late pops into place")
                        self.assertEqual(times[-1], layer["op"],
                                         "a property that ends early freezes mid-loop")

    def test_every_animated_property_loops_seamlessly(self):
        """First and last keyframe must match, or the loop visibly jumps.

        A layer with its own shorter window is exempt only if it is fully
        transparent at both ends of that window, which is how elements are
        allowed to cross the frame once instead of looping in view.
        """
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                invisible = (opacity_at(layer, 0) == 0 and opacity_at(layer, -1) == 0)
                for prop, value in self.layer_properties_of(layer):
                    if len(value["k"]) < 2:
                        continue
                    with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                        if prop == "ks.r":
                            continue  # Rotation may accumulate whole turns.
                        if invisible:
                            continue
                        first, last = value["k"][0]["s"], value["k"][-1]["s"]
                        if isinstance(first[0], dict):
                            self.assertEqual(first[0], last[0])
                        else:
                            for a, b in zip(first, last):
                                self.assertAlmostEqual(a, b, places=6)

    def test_windowed_layers_fade_at_both_ends(self):
        """Anything that does not span the loop must arrive and leave unseen."""
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                if layer["ip"] == animation["ip"] and layer["op"] == animation["op"]:
                    continue
                with self.subTest(f"{name}/{layer['nm']}"):
                    self.assertEqual(opacity_at(layer, 0), 0)
                    self.assertEqual(opacity_at(layer, -1), 0)

    def test_interpolation_handles_are_sized_to_the_value(self):
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for prop, value in self.layer_properties_of(layer):
                    with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                        for frame in value["k"][:-1]:
                            self.assertEqual(len(frame["i"]["x"]), len(frame["s"]))
                            self.assertEqual(len(frame["o"]["y"]), len(frame["s"]))
                        self.assertNotIn("i", value["k"][-1],
                                         "the final keyframe holds; it needs no handles")

    def test_easing_handles_are_valid_bezier_controls(self):
        """An out-of-range handle makes lottie-ios fall back to a linear guess."""
        eased = 0
        for name, animation in self.animations.items():
            for layer in animation["layers"]:
                for prop, value in self.layer_properties_of(layer):
                    with self.subTest(f"{name}/{layer['nm']}/{prop}"):
                        for frame in value["k"][:-1]:
                            for handle in (frame["i"], frame["o"]):
                                for axis in ("x", "y"):
                                    for component in handle[axis]:
                                        self.assertGreaterEqual(component, 0)
                                        self.assertLessEqual(component, 1)
                            if frame["o"]["x"][0] != 0.5 or frame["i"]["x"][0] != 0.5:
                                eased += 1
        self.assertGreater(eased, 0, "nothing uses real easing; everything is linear")

    # -- budget -----------------------------------------------------------

    def test_written_files_match_the_generator(self):
        for name, animation in self.animations.items():
            path = create_lottie.OUTPUT / (name + ".json")
            with self.subTest(name):
                self.assertTrue(path.exists(), "run Scripts/create_lottie.py")
                self.assertEqual(json.loads(path.read_text()), json.loads(json.dumps(animation)))

    def test_files_stay_within_the_bundle_budget(self):
        total = 0
        for name in self.animations:
            path = create_lottie.OUTPUT / (name + ".json")
            size = path.stat().st_size / 1024
            total += size
            with self.subTest(name):
                self.assertLess(size, MAX_FILE_KB, "keyframe sampling is too dense")
        self.assertLess(total, MAX_TOTAL_KB)


if __name__ == "__main__":
    unittest.main()
