#!/usr/bin/env python3
"""Author the bundled Lottie animations offline.

Nothing is downloaded and no design tool is required: each animation is written
as Bodymovin-compatible JSON. Three rules hold everywhere.

* **Seamless loops.** Every element's cycle divides the composition length
  exactly, and the final keyframe of every animated property is copied from the
  first. Elements that cross the frame once instead of looping are given their
  own layer window (`ip`/`op`) and fade to nothing at both ends of it.
* **Local authoring.** Every shape is drawn around its own origin and placed by
  its layer transform, so rotation, scale, and gradient coordinates all share
  one space.
* **Real easing.** Gestures use bezier handles on sparse keyframes; cyclic
  motion is sampled from functions that already carry their own easing, because
  a wrapped cycle cannot be expressed as a handful of eased keys.

Soft light is gradient fills with alpha ramps (`ty: "gf"`), not stacks of flat
ellipses; depth is parallax between near and far bands rather than one plane of
identical particles.

Scene canvases are portrait 1179 x 2556 rendered aspect-fill: keep anything that
matters above ~0.55H, because narrative text overlays the lower half. The two
accents are hosted aspect-fit in small frames and carry their own canvas sizes.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "PlayScript/Resources/Lottie"
FR = 60
W, H = 1179, 2556

# Warm and literary. Tense scenes cool toward desaturated plum, never neon.
CREAM = 0xFCF5F0
ROSE = 0x9D4057
PLUM = 0x5B4258
SOFT_RED = 0xC96A6A
MOONLIGHT = 0xE9D5B5
PETAL_NEAR = 0xF2DCD8
PETAL_MID = 0xE3B9BE
PETAL_FAR = 0xA8919E
EMBER = 0xD2621F
AMBER = 0xFFC27A
CANDLE_CORE = 0xFFF3D2
CANDLE_BASE = 0x7C8FB8
TOMB_LIGHT = 0xB6BDD5
TOMB_MIST = 0x8E93AC
DAWN_SUN = 0xFFC98F
DAWN_MIST = 0xFFE2CB
FEATHER = 0x453748
PAPER_LIT = 0xFFF7EC
PAPER_SHADE = 0xE3CDB4
ENVELOPE = 0xD9C3AE
ENVELOPE_SHADE = 0xBBA189
INK = 0x8C6A62

# Bezier timing handles: (out.x, out.y, in.x, in.y) for the segment that starts
# at the keyframe carrying them, matching CSS cubic-bezier(x1, y1, x2, y2).
LINEAR = (0.5, 0.5, 0.5, 0.5)
EASE = (0.42, 0.0, 0.58, 1.0)
EASE_OUT = (0.0, 0.0, 0.52, 1.0)
EASE_IN = (0.48, 0.0, 1.0, 1.0)


# --------------------------------------------------------------------------
# Primitives
# --------------------------------------------------------------------------

def quantize(value, places=2):
    """Trim float noise. Halves the file size and costs nothing visible."""
    if isinstance(value, float):
        return round(value, places)
    if isinstance(value, list):
        return [quantize(item, places) for item in value]
    if isinstance(value, dict):
        return {key: quantize(item, places) for key, item in value.items()}
    return value


def rgba(hex_value, alpha=1.0):
    return [((hex_value >> 16) & 255) / 255, ((hex_value >> 8) & 255) / 255,
            (hex_value & 255) / 255, alpha]


def static(value):
    return {"a": 0, "k": quantize(value)}


def animated(keys, ease=LINEAR):
    """Keyframes as (frame, value) or (frame, value, ease-handles)."""
    frames = []
    for index, key in enumerate(keys):
        time, value = key[0], key[1]
        values = quantize(value if isinstance(value, list) else [value])
        frame = {"t": round(time), "s": values}
        if index < len(keys) - 1:
            out_x, out_y, in_x, in_y = key[2] if len(key) > 2 else ease
            count = len(values)
            frame["o"] = {"x": [out_x] * count, "y": [out_y] * count}
            frame["i"] = {"x": [in_x] * count, "y": [in_y] * count}
        frames.append(frame)
    times = [frame["t"] for frame in frames]
    assert times == sorted(set(times)), f"keyframe times collide: {times}"
    return {"a": 1, "k": frames}


def cycle(start, end, step, function):
    """Sample a function whose cycle fills [start, end]; ends match exactly."""
    keys = [(t, function((t - start) / (end - start))) for t in range(start, end, step)]
    keys.append((end, keys[0][1]))
    return keys


def crossing(start, end, step, function):
    """Sample a one-shot gesture inside a layer window that fades at both ends."""
    keys = [(t, function((t - start) / (end - start))) for t in range(start, end, step)]
    keys.append((end, function(1.0)))
    return keys


def transform(position=None, opacity=100, rotation=0, scale=None, anchor=None):
    return {
        "o": opacity if isinstance(opacity, dict) else static(opacity),
        "r": rotation if isinstance(rotation, dict) else static(rotation),
        "p": position if isinstance(position, dict) else static(list(position or [0, 0])),
        "a": anchor if isinstance(anchor, dict) else static(list(anchor or [0, 0])),
        "s": scale if isinstance(scale, dict) else static(list(scale or [100, 100])),
    }


def group(items, name="group"):
    """A shape group. Core Animation requires exactly one path item per group."""
    return {"ty": "gr", "nm": name, "bm": 0, "hd": False, "it": items + [{
        "ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]),
        "r": static(0), "o": static(100), "sk": static(0), "sa": static(0), "nm": "transform"}]}


def fill(color, opacity=100):
    return {"ty": "fl", "c": static(color), "o": opacity if isinstance(opacity, dict)
            else static(opacity), "r": 1, "bm": 0, "nm": "fill"}


def stroke(color, width, opacity=100):
    return {"ty": "st", "c": static(color), "o": opacity if isinstance(opacity, dict)
            else static(opacity), "w": width if isinstance(width, dict) else static(width),
            "lc": 2, "lj": 2, "bm": 0, "nm": "stroke"}


def gradient(stops, start, end, radial=False, opacity=100):
    """A gradient fill. `stops` is [(location, hex colour, alpha)].

    Bodymovin packs the ramp as repeating [location, r, g, b] for each colour
    stop, followed by repeating [location, alpha]. The alpha ramp is what turns
    a hard-edged shape into light.
    """
    colours, alphas = [], []
    for location, hex_value, alpha in stops:
        red, green, blue, _ = rgba(hex_value)
        colours += [location, red, green, blue]
        alphas += [location, alpha]
    return {"ty": "gf", "o": opacity if isinstance(opacity, dict) else static(opacity),
            "r": 1, "bm": 0, "nm": "gradient", "t": 2 if radial else 1,
            "g": {"p": len(stops), "k": static(colours + alphas)},
            "s": static(list(start)), "e": static(list(end)),
            "h": static(0), "a": static(0)}


def trim(end, start=0, offset=0):
    """Trim paths: draws a stroke on by animating its end from 0 to 100."""
    return {"ty": "tm", "s": start if isinstance(start, dict) else static(start),
            "e": end if isinstance(end, dict) else static(end),
            "o": offset if isinstance(offset, dict) else static(offset),
            "m": 1, "nm": "trim"}


def bez(points, closed=True):
    """points: [(vertex, in-tangent, out-tangent)], tangents relative to vertex."""
    return {"i": [quantize(list(p[1])) for p in points],
            "o": [quantize(list(p[2])) for p in points],
            "v": [quantize(list(p[0])) for p in points], "c": closed}


def polygon(vertices, closed=True):
    return bez([(v, (0, 0), (0, 0)) for v in vertices], closed)


def path_item(shape):
    return {"ty": "sh", "d": 1, "ks": static(shape), "nm": "path"}


def morph(keys, ease=LINEAR):
    """keys: (frame, bezier dict). Vertex counts must match across keyframes."""
    frames = []
    for index, key in enumerate(keys):
        frame = {"t": round(key[0]), "s": [key[1]]}
        if index < len(keys) - 1:
            out_x, out_y, in_x, in_y = key[2] if len(key) > 2 else ease
            frame["o"] = {"x": [out_x], "y": [out_y]}
            frame["i"] = {"x": [in_x], "y": [in_y]}
        frames.append(frame)
    return {"ty": "sh", "d": 1, "ks": {"a": 1, "k": frames}, "nm": "path"}


def ellipse_item(size):
    return {"ty": "el", "d": 1, "s": size if isinstance(size, dict) else static(list(size)),
            "p": static([0, 0]), "nm": "ellipse"}


def glow(radius, stops, opacity=100):
    """A soft radial light: one ellipse, one gradient, alpha falling to nothing.

    The ellipse stays circular so its edge lands exactly where the gradient's
    alpha reaches zero; squashing it here instead would clip the ramp and leave
    a hard edge. Flatten a glow with the layer's scale, which carries the
    gradient with it.
    """
    return group([ellipse_item((radius * 2, radius * 2)),
                  gradient(stops, (0, 0), (radius, 0), radial=True, opacity=opacity)],
                 "glow")


def squashed(scale, squash):
    """Flatten an animated or static scale, keeping both components present."""
    if isinstance(scale, dict):
        for frame in scale["k"]:
            frame["s"] = [frame["s"][0], round(frame["s"][1] * squash, 2)]
        return scale
    return [scale[0], round(scale[1] * squash, 2)]


def noise(index, salt):
    value = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
    return value - math.floor(value)


def ease_out(u, power=2.2):
    return 1.0 - (1.0 - u) ** power


def fade(u, rise, fall):
    """A 0 -> 1 -> 0 envelope that is exactly 0 at both ends of the cycle."""
    if u <= 0.0 or u >= 1.0:
        return 0.0
    return max(0.0, min(1.0, u / rise, (1.0 - u) / fall))


class Scene:
    """Layers are added back to front; Lottie draws the first layer on top."""

    def __init__(self, name, loop, width=W, height=H):
        self.name, self.loop, self.width, self.height = name, loop, width, height
        self._layers = []

    def add(self, name, shapes, ks, ip=0, op=None):
        self._layers.append({"ddd": 0, "ind": 0, "ty": 4, "nm": name, "sr": 1, "ks": ks,
                             "ao": 0, "shapes": shapes, "ip": ip,
                             "op": self.loop if op is None else op, "st": 0, "bm": 0})

    def build(self):
        layers = list(reversed(self._layers))
        for index, layer in enumerate(layers):
            layer["ind"] = index + 1
        return {"v": "5.7.4", "fr": FR, "ip": 0, "op": self.loop,
                "w": self.width, "h": self.height, "nm": self.name, "ddd": 0,
                "assets": [], "layers": layers, "markers": []}


# --------------------------------------------------------------------------
# Scenes
# --------------------------------------------------------------------------

def orchard():
    """Moonlight over the orchard, and petals turning as they fall through it."""
    loop = 900
    scene = Scene("orchard", loop)
    moon_x, moon_y = W * 0.25, H * 0.13 + W * 0.06

    # Two hazes around the drawn moon, breathing out of step so neither reads
    # as a pulse. Both sit behind everything else.
    scene.add("moon-haze-wide", [glow(760, [
        (0.0, MOONLIGHT, 0.16), (0.30, MOONLIGHT, 0.09),
        (0.62, 0xD9CBE0, 0.035), (1.0, CREAM, 0.0)])],
        transform(position=[moon_x, moon_y],
                  scale=squashed(animated(cycle(0, loop, 45, lambda p: (
                      [98 + 7 * math.sin(p * math.pi * 2),
                       98 + 7 * math.sin(p * math.pi * 2)]))), 0.86),
                  opacity=animated(cycle(0, loop, 45, lambda p: round(
                      74 + 20 * math.sin(p * math.pi * 2 + 1.1), 1)))))
    scene.add("moon-haze-core", [glow(300, [
        (0.0, 0xFFF6E4, 0.30), (0.34, MOONLIGHT, 0.15),
        (1.0, MOONLIGHT, 0.0)])],
        transform(position=[moon_x, moon_y],
                  scale=animated(cycle(0, loop, 30, lambda p: (
                      [96 + 9 * math.sin(p * math.pi * 2 * 2 + 0.6),
                       96 + 9 * math.sin(p * math.pi * 2 * 2 + 0.6)]))),
                  opacity=animated(cycle(0, loop, 30, lambda p: round(
                      80 + 18 * math.sin(p * math.pi * 2 * 2 + 2.4), 1)))))

    # Three depth bands. Far petals are small, cool, slow and faint; near petals
    # are large, warm and quick, and drift further sideways -- the parallax is
    # what stops the fall reading as one flat plane of confetti.
    bands = [
        ("far", 7, (13, 20), PETAL_FAR, 30, 1, 150, 11),
        ("mid", 6, (21, 31), PETAL_MID, 52, 1, 230, 17),
        ("near", 4, (38, 54), PETAL_NEAR, 34, 2, 320, 23),
    ]
    for band, count, (small, large), colour, alpha, turns, drift, salt in bands:
        for i in range(count):
            seed_x, seed_y, seed_r = noise(i, salt), noise(i, salt + 1), noise(i, salt + 2)
            width = small + (large - small) * seed_r
            height = width * 1.55
            base_x = W * (0.06 + 0.88 * seed_x)
            phase = seed_y
            spins = (1 if seed_r > 0.45 else -1) * turns
            sway = drift * (0.6 + 0.4 * seed_r)

            def position(p, phase=phase, base_x=base_x, sway=sway, seed_x=seed_x, turns=turns):
                c = (p * turns + phase) % 1.0
                # A slow sway with a smaller, faster wobble riding on it: a petal
                # caught by air, not a pendulum.
                x = (base_x + sway * math.sin(c * math.pi * 2 + seed_x * 6.28)
                     + sway * 0.28 * math.sin(c * math.pi * 6 + seed_x * 2.2))
                # Fall eases slightly as the petal spills sideways.
                y = -180 + (c + 0.06 * math.sin(c * math.pi * 4)) * (H + 360)
                return [x, y]

            def opacity(p, phase=phase, alpha=alpha, turns=turns):
                return round(fade((p * turns + phase) % 1.0, 0.14, 0.18) * alpha, 1)

            def flip(p, phase=phase, spins=spins, turns=turns):
                # The petal turns edge-on and back as it tumbles, so its width
                # collapses on the same beat as its rotation.
                angle = ((p * turns + phase) % 1.0) * math.pi * 2 * abs(spins)
                return [round(26 + 74 * abs(math.cos(angle)), 1), 100]

            scene.add(f"petal-{band}-{i}", [group([
                path_item(petal_path(width, height)),
                fill(rgba(colour))], "petal")],
                transform(position=animated(cycle(0, loop, 15, position)),
                          opacity=animated(cycle(0, loop, 25, opacity)),
                          scale=animated(cycle(0, loop, 15, flip)),
                          rotation=animated([(0, 0), (loop, 360 * spins * turns)])))
    return scene.build()


def petal_path(width, height):
    """A leaf: rounded shoulder, narrow tip. Not an ellipse."""
    return bez([
        ((0, -height * 0.5), (-width * 0.42, -height * 0.05), (width * 0.42, -height * 0.05)),
        ((width * 0.5, -height * 0.04), (0, -height * 0.26), (0, height * 0.22)),
        ((0, height * 0.5), (width * 0.13, -height * 0.22), (-width * 0.13, -height * 0.22)),
        ((-width * 0.5, -height * 0.04), (0, height * 0.22), (0, -height * 0.26)),
    ])


def chamber():
    """A candle that never repeats a breath, and gutters twice before it settles."""
    loop = 720
    scene = Scene("chamber", loop)
    # The drawn candle occupies 0.707-0.732 W and begins at 0.409 H.
    flame_x, flame_y = W * 0.7195, H * 0.409

    def flicker(p, lag=0.0):
        a = (p - lag) * math.pi * 2
        return (math.sin(a * 7) * 0.30 + math.sin(a * 11 + 1.1) * 0.22
                + math.sin(a * 17 + 2.3) * 0.12 + math.sin(a * 3 + 0.4) * 0.20)

    def gutter(p):
        """Twice a loop the flame ducks, as if a door moved somewhere."""
        dip = max(0.0, math.sin(p * math.pi * 2 * 2 + 0.9)) ** 12
        return 1.0 - 0.42 * dip

    # Light first, because it has to sit behind the flame that makes it.
    scene.add("wash", [glow(940, [
        (0.0, AMBER, 0.13), (0.28, 0xE79B52, 0.07),
        (0.66, ROSE, 0.025), (1.0, PLUM, 0.0)])],
        transform(position=[flame_x - 70, flame_y - 150],
                  opacity=animated(cycle(0, loop, 12, lambda p: round(
                      (72 + flicker(p, 0.06) * 12) * gutter(p), 1))),
                  scale=squashed(animated(cycle(0, loop, 12, lambda p: (
                      [100 + flicker(p, 0.08) * 3, 100 + flicker(p, 0.08) * 2.4]))), 1.08)))
    scene.add("halo", [glow(400, [
        (0.0, 0xFFD9A0, 0.26), (0.32, AMBER, 0.14),
        (0.70, 0xE08A45, 0.04), (1.0, ROSE, 0.0)])],
        transform(position=[flame_x, flame_y - 70],
                  opacity=animated(cycle(0, loop, 8, lambda p: round(
                      (82 + flicker(p, 0.03) * 16) * gutter(p), 1))),
                  scale=squashed(animated(cycle(0, loop, 8, lambda p: (
                      [100 + flicker(p, 0.03) * 7, 100 + flicker(p, 0.03) * 5.5]))), 0.95)))
    scene.add("corona", [glow(170, [
        (0.0, CANDLE_CORE, 0.42), (0.40, AMBER, 0.20), (1.0, 0xE07A2A, 0.0)])],
        transform(position=[flame_x, flame_y - 52],
                  opacity=animated(cycle(0, loop, 6, lambda p: round(
                      (86 + flicker(p) * 14) * gutter(p), 1))),
                  scale=animated(cycle(0, loop, 6, lambda p: (
                      [100 + flicker(p) * 11, 100 + flicker(p) * 9])))))

    # The flame body: a filled, morphing teardrop lit from its base upward.
    nominal = 156
    body_keys, core_keys = [], []
    for t in range(0, loop, 6):
        p = t / loop
        f, g = flicker(p), gutter(p)
        height = (nominal + f * 30) * g
        width = (58 + f * 5) * (0.94 + 0.06 * g)
        body_keys.append((t, flame_path(height, width, f * 9, 1.0 + f * 0.05)))
        core_keys.append((t, flame_path(height * 0.52, width * 0.44, f * 4, 1.0)))
    body_keys.append((loop, body_keys[0][1]))
    core_keys.append((loop, core_keys[0][1]))

    def lean(p):
        return round(math.sin(p * math.pi * 2) * 2.4 + math.sin(p * math.pi * 6 + 2.0) * 1.2, 2)

    scene.add("flame", [group([
        morph(body_keys),
        gradient([(0.0, EMBER, 0.45), (0.16, 0xE8913A, 0.82), (0.44, AMBER, 0.95),
                  (0.76, 0xFFE3AC, 0.92), (1.0, 0xFFF9EC, 0.55)],
                 (0, nominal * 0.08), (0, -nominal * 1.02))], "flame-body")],
        transform(position=[flame_x, flame_y], rotation=animated(cycle(0, loop, 12, lean))))
    scene.add("flame-core", [group([
        morph(core_keys),
        gradient([(0.0, 0xFFE0A8, 0.30), (0.45, CANDLE_CORE, 0.80), (1.0, CREAM, 0.42)],
                 (0, nominal * 0.04), (0, -nominal * 0.52))], "core-body")],
        transform(position=animated(cycle(0, loop, 6, lambda p: (
                      [flame_x + flicker(p) * 2.5, flame_y - 6 - flicker(p) * 5]))),
                  rotation=animated(cycle(0, loop, 12, lean)),
                  opacity=animated(cycle(0, loop, 6, lambda p: round(
                      72 + flicker(p) * 16, 1)))))
    # The cool crescent every real candle has where the wax meets the flame.
    scene.add("flame-foot", [glow(34, [
        (0.0, CANDLE_BASE, 0.34), (0.5, 0x6F82AE, 0.14), (1.0, PLUM, 0.0)])],
        transform(position=[flame_x, flame_y - 10],
                  opacity=animated(cycle(0, loop, 10, lambda p: round(
                      (56 + flicker(p, 0.02) * 22) * gutter(p), 1))),
                  scale=squashed(animated(cycle(0, loop, 10, lambda p: (
                      [100 + flicker(p) * 9, 100 + flicker(p) * 6]))), 0.72)))
    return scene.build()


def flame_path(height, width, tip_shift, waist):
    return bez([
        ((tip_shift, -height), (-width * 0.15, height * 0.16), (width * 0.15, height * 0.16)),
        ((width * 0.50 * waist, -height * 0.40), (width * 0.05, -height * 0.20),
         (-width * 0.03, height * 0.17)),
        ((width * 0.33, -height * 0.03), (width * 0.09, -height * 0.11),
         (-width * 0.09, height * 0.04)),
        ((0, height * 0.07), (width * 0.18, 0), (-width * 0.18, 0)),
        ((-width * 0.33, -height * 0.03), (width * 0.09, height * 0.04),
         (-width * 0.09, -height * 0.11)),
        ((-width * 0.50 * waist, -height * 0.40), (width * 0.03, height * 0.17),
         (-width * 0.05, -height * 0.20)),
    ])


def tomb():
    """A shaft of light that breathes unevenly, and mist crawling over stone."""
    loop = 1440
    scene = Scene("tomb", loop)

    # A cool plum wash, so the whole scene sits colder than the others.
    scene.add("cold-wash", [glow(900, [
        (0.0, TOMB_LIGHT, 0.09), (0.40, PLUM, 0.05), (1.0, 0x1B1B28, 0.0)])],
        transform(position=[W * 0.52, H * 0.16], scale=[100, 120],
                  opacity=animated(cycle(0, loop, 60, lambda p: round(
                      72 + 22 * math.sin(p * math.pi * 2 + 0.7), 1)))))

    # The pool the shaft lands in, on the slab. Faint, and it answers the shaft
    # a beat late rather than pulsing with it.
    scene.add("pool", [glow(360, [
        (0.0, 0xD5DAE8, 0.15), (0.35, TOMB_LIGHT, 0.07), (1.0, PLUM, 0.0)])],
        transform(position=[W * 0.63, H * 0.565],
                  scale=[128, 30],
                  opacity=animated([
                      (0, 34, EASE), (round(loop * 0.38), 96, EASE),
                      (round(loop * 0.56), 58, EASE), (round(loop * 0.80), 82, EASE),
                      (loop, 34)])))

    # Two shafts, unequal, breathing on different curves. The gradient runs
    # across the shaft so its edges dissolve instead of ending in a line.
    shaft_wide = polygon([[W * 0.26, 0], [W * 0.53, 0], [W * 0.82, H * 0.575],
                          [W * 0.45, H * 0.575]])
    scene.add("shaft", [group([
        path_item(shaft_wide),
        gradient([(0.0, TOMB_LIGHT, 0.0), (0.22, TOMB_LIGHT, 0.06),
                  (0.50, 0xE2E6F2, 0.11), (0.78, TOMB_LIGHT, 0.05), (1.0, TOMB_LIGHT, 0.0)],
                 (W * 0.30, H * 0.30), (W * 0.72, H * 0.30))], "shaft-body")],
        transform(opacity=animated([
            (0, 40, EASE), (round(loop * 0.30), 100, EASE_IN),
            (round(loop * 0.48), 62, EASE), (round(loop * 0.72), 88, EASE_IN),
            (loop, 40)])))
    shaft_thin = polygon([[W * 0.34, 0], [W * 0.43, 0], [W * 0.63, H * 0.56],
                          [W * 0.50, H * 0.56]])
    scene.add("shaft-core", [group([
        path_item(shaft_thin),
        gradient([(0.0, TOMB_LIGHT, 0.0), (0.5, 0xEDEFF7, 0.13), (1.0, TOMB_LIGHT, 0.0)],
                 (W * 0.36, H * 0.28), (W * 0.60, H * 0.28))], "core-body")],
        transform(opacity=animated([
            (0, 30, EASE), (round(loop * 0.22), 84, EASE), (round(loop * 0.44), 46, EASE),
            (round(loop * 0.66), 96, EASE), (round(loop * 0.86), 52, EASE), (loop, 30)])))

    # The quirk: once a loop a brightening travels down the shaft, as if
    # something passed the opening far above.
    scene.add("shaft-ripple", [glow(230, [
        (0.0, 0xF0F2FA, 0.16), (0.5, TOMB_LIGHT, 0.06), (1.0, TOMB_LIGHT, 0.0)])],
        transform(position=animated(cycle(0, loop, 24, lambda p: (
                      [W * (0.40 + 0.20 * p), H * (-0.05 + 0.66 * p)]))),
                  opacity=animated(cycle(0, loop, 24, lambda p: round(
                      fade(p, 0.18, 0.30) * 62, 1))),
                  scale=[100, 34], rotation=-22))

    # Mist across the stone, three depths crawling at different speeds.
    for i, (band_y, speed, width, alpha, direction) in enumerate([
            (0.500, 1, 520, 0.085, 1), (0.556, 1, 660, 0.070, -1), (0.598, 2, 430, 0.055, 1)]):
        phase = i / 3

        def position(p, band_y=band_y, speed=speed, direction=direction, phase=phase, i=i):
            c = (p * speed + phase) % 1.0
            travel = c if direction > 0 else 1.0 - c
            return [W * (-0.35 + 1.7 * travel),
                    H * band_y + math.sin(c * math.pi * 2 + i) * H * 0.006]

        def opacity(p, speed=speed, phase=phase):
            return round(fade((p * speed + phase) % 1.0, 0.28, 0.28) * 100, 1)

        scene.add(f"mist-{i}", [glow(width, [
            (0.0, TOMB_MIST, alpha), (0.45, TOMB_MIST, alpha * 0.55),
            (1.0, PLUM, 0.0)])],
            transform(position=animated(cycle(0, loop, 30, position)),
                      opacity=animated(cycle(0, loop, 30, opacity)),
                      scale=squashed(animated(cycle(0, loop, 60, lambda p, i=i: (
                          [100 + 8 * math.sin(p * math.pi * 2 + i * 2),
                           100 + 14 * math.sin(p * math.pi * 2 * 2 + i)]))), 0.16)))
    return scene.build()


def road():
    """Dawn lifting off the road, and a flock that crosses once and is gone."""
    loop = 1800
    scene = Scene("road", loop)
    sun_x, sun_y = W * 0.49, H * 0.435

    scene.add("dawn-wash", [glow(940, [
        (0.0, DAWN_SUN, 0.20), (0.26, 0xF2A97E, 0.11),
        (0.62, ROSE, 0.04), (1.0, PLUM, 0.0)])],
        transform(position=[sun_x, sun_y],
                  scale=squashed(animated(cycle(0, loop, 60, lambda p: (
                      [99 + 6 * math.sin(p * math.pi * 2),
                       99 + 5 * math.sin(p * math.pi * 2)]))), 0.78),
                  opacity=animated(cycle(0, loop, 60, lambda p: round(
                      80 + 18 * math.sin(p * math.pi * 2 + 0.8), 1)))))
    scene.add("dawn-core", [glow(300, [
        (0.0, 0xFFE9CE, 0.34), (0.38, DAWN_SUN, 0.16), (1.0, SOFT_RED, 0.0)])],
        transform(position=[sun_x, sun_y + H * 0.006],
                  scale=squashed(animated(cycle(0, loop, 40, lambda p: (
                      [98 + 8 * math.sin(p * math.pi * 2 * 2 + 1.4),
                       98 + 8 * math.sin(p * math.pi * 2 * 2 + 1.4)]))), 0.72),
                  opacity=animated(cycle(0, loop, 40, lambda p: round(
                      84 + 14 * math.sin(p * math.pi * 2 * 2), 1)))))

    # Two light wedges leaning off the sun. Barely there, and never together.
    for i, (spread, tilt, phase) in enumerate([(0.16, -0.13, 0.0), (0.11, 0.11, 0.45)]):
        top_x = sun_x + W * tilt * 2.2
        wedge = polygon([[sun_x - W * 0.02, sun_y], [sun_x + W * 0.02, sun_y],
                         [top_x + W * spread, -H * 0.02], [top_x - W * spread, -H * 0.02]])
        scene.add(f"ray-{i}", [group([
            path_item(wedge),
            gradient([(0.0, 0xFFE8CC, 0.09), (0.55, DAWN_MIST, 0.04), (1.0, DAWN_MIST, 0.0)],
                     (sun_x, sun_y), (top_x, -H * 0.02))], "ray-body")],
            transform(opacity=animated(cycle(0, loop, 45, lambda p, phase=phase: round(
                48 + 44 * math.sin((p + phase) * math.pi * 2), 1)))))

    # The flock crosses once, then a single straggler much later -- the loop is
    # 30 seconds, so nothing here reads as a repeating carousel.
    flights = [
        (240, 1020, 0.150, 0.196, 44, 6.0, 74, 2.1, 0),
        (300, 1080, 0.176, 0.224, 38, 5.2, 62, 2.3, 1),
        (372, 1170, 0.128, 0.170, 31, 4.4, 50, 2.6, 2),
        (444, 1260, 0.200, 0.246, 26, 3.8, 40, 2.9, 3),
        (1290, 1740, 0.092, 0.126, 40, 5.6, 58, 1.9, 4),
    ]
    for start, end, from_y, to_y, span, weight, alpha, hertz, i in flights:
        seed = noise(i, 41)
        reverse = i == 4  # The straggler crosses the other way.
        beats = hertz * (end - start) / FR

        def wings(u, span=span, beats=beats, seed=seed):
            # Bursts of flapping separated by glides, rather than a metronome.
            burst = max(0.0, math.sin(u * math.pi * 2 * 2.0 + seed * 3.0)) ** 0.55
            drive = math.sin(u * math.pi * 2 * beats + seed * 6.28)
            lift = span * (0.16 + 0.62 * burst) * drive
            return wing_path(span, lift, -span * 0.06 + lift * 0.06)

        def position(u, from_y=from_y, to_y=to_y, reverse=reverse, seed=seed):
            travel = 1.0 - u if reverse else u
            x = W * (-0.18 + 1.36 * travel)
            y = H * (from_y + (to_y - from_y) * ease_out(u, 1.4))
            return [x, y + math.sin(u * math.pi * 2 * 2.5 + seed * 6.28) * H * 0.008]

        scene.add(f"bird-{i}", [group([
            morph(crossing(start, end, 4, wings)),
            stroke(rgba(FEATHER), weight)], "wing")],
            transform(position=animated(crossing(start, end, 8, position)),
                      opacity=animated(crossing(start, end, 8,
                                                lambda u, alpha=alpha: round(
                                                    fade(u, 0.14, 0.18) * alpha, 1)))),
            ip=start, op=end)

    # Mist lifting off the road, soft-edged and slow.
    for i, (band_y, width, alpha, speed) in enumerate([
            (0.470, 620, 0.10, 1), (0.512, 780, 0.075, 1), (0.548, 520, 0.055, 2)]):
        phase = i * 0.37

        def position(p, band_y=band_y, phase=phase, speed=speed, i=i):
            c = (p * speed + phase) % 1.0
            return [W * (-0.32 + 1.64 * c),
                    H * band_y + math.sin(c * math.pi * 2 + i * 1.7) * H * 0.005]

        def opacity(p, phase=phase, speed=speed):
            return round(fade((p * speed + phase) % 1.0, 0.26, 0.30) * 100, 1)

        scene.add(f"mist-{i}", [glow(width, [
            (0.0, DAWN_MIST, alpha), (0.42, 0xF7D9BE, alpha * 0.5), (1.0, ROSE, 0.0)])],
            transform(position=animated(cycle(0, loop, 36, position)),
                      opacity=animated(cycle(0, loop, 36, opacity)),
                      scale=squashed(animated(cycle(0, loop, 72, lambda p, i=i: (
                          [100 + 7 * math.sin(p * math.pi * 2 + i),
                           100 + 16 * math.sin(p * math.pi * 2 * 2 + i * 2)]))), 0.14)))
    return scene.build()


def wing_path(span, lift, sweep):
    return bez([
        ((-span, lift * 0.34), (-span * 0.26, -lift * 0.18), (span * 0.26, lift * 0.14)),
        ((-span * 0.52, -lift), (-span * 0.17, -lift * 0.10), (span * 0.17, lift * 0.10)),
        ((0, sweep), (-span * 0.20, -lift * 0.20), (span * 0.20, -lift * 0.20)),
        ((span * 0.52, -lift), (-span * 0.17, lift * 0.10), (span * 0.17, -lift * 0.10)),
        ((span, lift * 0.34), (-span * 0.26, lift * 0.14), (span * 0.26, -lift * 0.18)),
    ], closed=False)


def letter():
    """The Friar's letter: the flap opens, the sheet rises, the hand writes."""
    # Hosted aspect-fit in a 170 x 150 frame, so the canvas matches that ratio
    # instead of the portrait scene size -- otherwise it renders as a sliver.
    loop = 660
    width, height = 612, 540
    scene = Scene("letter", loop, width, height)
    cx, cy = width / 2, height * 0.52

    def at(fraction):
        return round(loop * fraction)

    scene.add("glow", [glow(250, [
        (0.0, 0xFFE0B8, 0.26), (0.34, AMBER, 0.12), (1.0, ROSE, 0.0)])],
        transform(position=[cx, cy - 20],
                  opacity=animated([(0, 58, EASE), (at(0.34), 100, EASE),
                                    (at(0.70), 76, EASE), (loop, 58)]),
                  scale=squashed(animated([(0, [92, 92], EASE), (at(0.38), [104, 104], EASE),
                                           (at(0.74), [96, 96], EASE), (loop, [92, 92])]),
                                 0.92)))

    # The flap hinges at the envelope's top edge and folds back out of the way.
    flap_y = cy + 22
    scene.add("flap", [group([
        path_item(bez([((-150, 0), (0, 0), (0, 0)),
                       ((150, 0), (0, 0), (0, 0)),
                       ((0, 96), (34, -14), (-34, -14))])),
        gradient([(0.0, ENVELOPE, 1.0), (1.0, ENVELOPE_SHADE, 1.0)], (0, 0), (0, 96))],
        "flap-body")],
        transform(position=[cx, flap_y],
                  rotation=animated([(0, 0, EASE), (at(0.08), 0, EASE_OUT),
                                     (at(0.24), -168, EASE), (at(0.78), -168, EASE_IN),
                                     (at(0.94), 0, EASE), (loop, 0)])))

    # The sheet: a slight curl along the bottom edge, lit from the upper left.
    sheet = bez([
        ((-136, -96), (0, 0), (0, 0)),
        ((136, -96), (0, 0), (0, 0)),
        ((136, 88), (0, -18), (0, 10)),
        ((0, 104), (46, -4), (-46, -4)),
        ((-136, 88), (0, 10), (0, -18)),
    ])

    def sheet_lift(p):
        """Rises with a long settle, waits, then sinks back."""
        if p < 0.14:
            return 0.0
        if p < 0.44:
            return ease_out((p - 0.14) / 0.30, 2.6)
        if p < 0.74:
            return 1.0
        if p < 0.92:
            return 1.0 - ease_out((p - 0.74) / 0.18, 1.6)
        return 0.0

    def sheet_position(p):
        return [cx, cy + 34 - sheet_lift(p) * 150]

    scene.add("sheet", [group([
        path_item(sheet),
        gradient([(0.0, PAPER_LIT, 1.0), (0.55, 0xF6E6D2, 1.0), (1.0, PAPER_SHADE, 1.0)],
                 (-136, -96), (136, 104))], "sheet-body")],
        transform(position=animated(cycle(0, loop, 10, sheet_position)),
                  opacity=animated([(0, 0, EASE_OUT), (at(0.16), 0, EASE_OUT),
                                    (at(0.28), 100, EASE), (at(0.80), 100, EASE_IN),
                                    (at(0.93), 0, EASE), (loop, 0)]),
                  rotation=animated(cycle(0, loop, 20, lambda p: round(
                      math.sin(p * math.pi * 2) * 2.2 + math.sin(p * math.pi * 6) * 0.7, 2)))))

    # Four lines of hand, drawn on in sequence with trim paths.
    line_groups = []
    for i in range(4):
        length = 196 - i * 16
        y = -44 + i * 40
        wobble = 5 - i
        line_groups.append(group([
            path_item(bez([
                ((-length / 2, y), (0, 0), (length * 0.12, -wobble)),
                ((-length * 0.16, y + wobble * 0.6), (-length * 0.12, -wobble),
                 (length * 0.12, wobble)),
                ((length * 0.20, y - wobble * 0.5), (-length * 0.12, wobble),
                 (length * 0.10, -wobble)),
                ((length / 2, y + wobble * 0.3), (-length * 0.12, -wobble * 0.4), (0, 0)),
            ], closed=False)),
            trim(animated([(0, 0, EASE), (at(0.26 + i * 0.045), 0, EASE_OUT),
                           (at(0.44 + i * 0.045), 100, EASE), (at(0.965), 100),
                           (loop, 0)])),
            stroke(rgba(INK), 7, opacity=62),
        ], f"line-{i}"))
    scene.add("writing", line_groups,
              transform(position=animated(cycle(0, loop, 10, sheet_position)),
                        opacity=animated([(0, 0, EASE_OUT), (at(0.22), 0, EASE),
                                          (at(0.32), 100, EASE_IN), (at(0.80), 100, EASE),
                                          (at(0.92), 0, EASE), (loop, 0)]),
                        rotation=animated(cycle(0, loop, 20, lambda p: round(
                            math.sin(p * math.pi * 2) * 2.2
                            + math.sin(p * math.pi * 6) * 0.7, 2)))))

    scene.add("envelope", [group([
        path_item(bez([((-150, -24), (0, 0), (0, 0)), ((150, -24), (0, 0), (0, 0)),
                       ((150, 96), (0, 0), (0, 0)), ((-150, 96), (0, 0), (0, 0))])),
        gradient([(0.0, ENVELOPE, 1.0), (0.62, 0xCFB79F, 1.0), (1.0, ENVELOPE_SHADE, 1.0)],
                 (-150, -24), (150, 96))], "envelope-body")],
        transform(position=[cx, cy + 46],
                  rotation=animated(cycle(0, loop, 24, lambda p: round(
                      math.sin(p * math.pi * 2 + 0.6) * 1.3, 2)))))
    scene.add("seal", [
        group([ellipse_item((66, 62)),
               gradient([(0.0, 0xC05E71, 1.0), (0.48, ROSE, 1.0), (1.0, 0x6F2A3C, 1.0)],
                        (-18, -18), (26, 26), radial=True)], "seal-body"),
    ], transform(position=[cx, cy + 46],
                 scale=animated([(0, [97, 97], EASE), (at(0.30), [104, 104], EASE),
                                 (at(0.66), [98, 98], EASE), (loop, [97, 97])])))
    return scene.build()


def thought():
    """Rings blooming under a decision, and two motes rising into the thought."""
    # Hosted aspect-fit behind the two choices, so the canvas is wide, not tall.
    loop = 540
    width, height = 1000, 620
    scene = Scene("thought", loop, width, height)
    cx, cy = width / 2, height / 2

    # Added first, so it sits behind everything: the presence the rings
    # come out of, breathing slowly under them.
    scene.add("presence", [glow(230, [
        (0.0, CREAM, 0.20), (0.36, 0xF0DAD8, 0.10), (1.0, ROSE, 0.0)])],
        transform(position=[cx, cy],
                  scale=squashed(animated([
                      (0, [92, 92], EASE), (round(loop * 0.42), [108, 108], EASE),
                      (round(loop * 0.74), [97, 97], EASE), (loop, [92, 92])]), 0.86),
                  opacity=animated([(0, 66, EASE), (round(loop * 0.34), 100, EASE),
                                    (round(loop * 0.72), 78, EASE), (loop, 66)])))

    # Four ripples, staggered a quarter loop apart. Each is authored as a
    # wrapped cycle sampled from an eased profile, so the stagger costs no
    # extra layers and the loop stays seamless.
    span = 0.74  # Fraction of the loop a single ring is alive for.
    for i in range(4):
        phase = i / 4

        def diameter(p, phase=phase):
            u = (p + phase) % 1.0
            if u >= span:
                # Invisible: glide back to the start size before the next bloom.
                return [70, 70]
            value = 70 + 490 * ease_out(u / span, 2.4)
            return [round(value, 1), round(value, 1)]

        def opacity(p, phase=phase):
            u = (p + phase) % 1.0
            if u >= span:
                return 0.0
            return round(min(1.0, u / 0.10) * (1.0 - u / span) ** 1.7 * 44, 1)

        def weight(p, phase=phase):
            u = (p + phase) % 1.0
            if u >= span:
                return 6.0
            return round(6.0 - 4.4 * ease_out(u / span, 1.6), 2)

        scene.add(f"ring-{i}", [group([
            {"ty": "el", "d": 1, "s": animated(cycle(0, loop, 9, diameter)),
             "p": static([0, 0]), "nm": "ellipse"},
            stroke(rgba(0xF0DAD8), animated(cycle(0, loop, 9, weight))),
        ], "ring")],
            transform(position=[cx, cy], opacity=animated(cycle(0, loop, 9, opacity))))

    # Two small motes drifting up into the centre: a thought arriving.
    for i, (offset_x, size, alpha, speed) in enumerate([(-0.17, 26, 30, 1), (0.21, 20, 22, 1)]):
        phase = 0.35 * i

        def position(p, offset_x=offset_x, phase=phase, speed=speed, i=i):
            u = (p * speed + phase) % 1.0
            return [cx + width * offset_x + math.sin(u * math.pi * 2 + i) * 16,
                    cy + height * (0.42 - 0.62 * ease_out(u, 1.25))]

        def mote_opacity(p, phase=phase, speed=speed, alpha=alpha):
            return round(fade((p * speed + phase) % 1.0, 0.22, 0.34) * alpha, 1)

        scene.add(f"mote-{i}", [glow(size, [
            (0.0, CREAM, 0.85), (0.5, 0xF0DAD8, 0.34), (1.0, ROSE, 0.0)])],
            transform(position=animated(cycle(0, loop, 12, position)),
                      opacity=animated(cycle(0, loop, 12, mote_opacity))))

    return scene.build()


def page_turn():
    """A one-shot flourish for the tap-to-continue button: ink catches light.

    Played once (not looped) when the reader taps to advance a page, so unlike
    every other accent here it does not need to loop seamlessly -- every layer
    simply fades in from nothing and back out to nothing, which keeps it exempt
    from the seamless-loop check while it swoops from one shape to another.
    Hosted aspect-fit in a small frame behind the button, so the canvas is a
    short, wide strip rather than the portrait scene size.
    """
    loop = 54  # 0.9s at 60fps -- a brief accent, not an ambient scene.
    width, height = 240, 96
    scene = Scene("accent-page-turn", loop, width, height)
    cx, cy = width / 2, height / 2

    def at(fraction):
        return round(loop * fraction)

    # A soft warm bloom behind the stroke, like light briefly touching a page.
    scene.add("glow", [glow(46, [
        (0.0, AMBER, 0.30), (0.42, EMBER, 0.14), (1.0, ROSE, 0.0)])],
        transform(position=[cx, cy],
                  opacity=animated([(0, 0, EASE_OUT), (at(0.24), 68, EASE),
                                    (at(0.64), 42, EASE), (loop, 0)]),
                  scale=squashed(animated([(0, [68, 68], EASE_OUT), (at(0.5), [116, 116], EASE),
                                           (loop, [90, 90])]), 0.8)))

    # A thin band of light catching the page edge, drawn on with a trim path.
    band = polygon([[-78, -4], [78, -4], [78, 4], [-78, 4]])
    scene.add("glint", [group([
        path_item(band),
        trim(animated([(0, 0, EASE), (at(0.46), 100, EASE_OUT), (loop, 100)])),
        gradient([(0.0, CREAM, 0.0), (0.42, MOONLIGHT, 0.55), (0.56, CREAM, 0.75),
                  (1.0, CREAM, 0.0)], (-78, 0), (78, 0))], "glint-body")],
        transform(position=[cx * 0.96, cy * 0.62], rotation=-13,
                  opacity=animated([(0, 0, EASE_OUT), (at(0.12), 0, EASE_OUT),
                                    (at(0.30), 85, EASE), (at(0.68), 55, EASE), (loop, 0)])))

    # The quill stroke itself: a single eased swoop, revealed by its own trim.
    stroke_path = bez([
        ((-82, 20), (0, 0), (24, -17)),
        ((-18, -9), (-21, 13), (23, -15)),
        ((44, -19), (-19, 11), (13, -7)),
        ((82, -4), (-9, 5), (0, 0)),
    ], closed=False)
    scene.add("stroke", [group([
        path_item(stroke_path),
        trim(animated([(0, 0, EASE), (at(0.58), 100, EASE_OUT), (loop, 100)])),
        stroke(rgba(INK), 5)], "stroke-body")],
        transform(position=[cx, cy * 1.02],
                  opacity=animated([(0, 0, EASE_OUT), (at(0.10), 0, EASE_OUT),
                                    (at(0.26), 78, EASE), (at(0.74), 78, EASE_IN), (loop, 0)])))
    return scene.build()


ANIMATIONS = {
    "scene-orchard": orchard,
    "scene-chamber": chamber,
    "scene-tomb": tomb,
    "scene-road": road,
    "accent-letter": letter,
    "accent-thought": thought,
    "accent-page-turn": page_turn,
}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, builder in ANIMATIONS.items():
        animation = builder()
        destination = OUTPUT / (name + ".json")
        destination.write_text(json.dumps(animation, separators=(",", ":")) + "\n")
        size = destination.stat().st_size / 1024
        total += size
        seconds = animation["op"] / FR
        print(f"{name}: {len(animation['layers'])} layers, {seconds:.0f}s loop, {size:.0f} KB")
    print(f"total {total / 1024:.2f} MB")
    print("Run python3 Scripts/create_project.py to bundle these with the app.")


if __name__ == "__main__":
    main()
