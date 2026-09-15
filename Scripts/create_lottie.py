#!/usr/bin/env python3
"""Author the bundled Lottie animations offline.

Nothing is downloaded and no design tool is required: each animation is written
as Bodymovin-compatible JSON with densely sampled keyframes, so motion stays
smooth under linear interpolation. Every loop is seamless by construction --
each element's cycle length divides the composition length exactly, so frame 0
and the final frame hold identical values.

Canvas coordinates are portrait 1179 x 2556; the app renders aspect-fill.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "PlayScript/Resources/Lottie"
FR = 60
W, H = 1179, 2556


def rgba(hex_value, alpha=1.0):
    return [((hex_value >> 16) & 255) / 255, ((hex_value >> 8) & 255) / 255,
            (hex_value & 255) / 255, alpha]


def static(value):
    return {"a": 0, "k": value}


def animated(keys):
    """Keyframes as (frame, value). Control points of 0.5 interpolate linearly."""
    frames = []
    for index, (time, value) in enumerate(keys):
        values = value if isinstance(value, list) else [value]
        frame = {"t": round(time), "s": values}
        if index < len(keys) - 1:
            count = len(values)
            frame["i"] = {"x": [0.5] * count, "y": [0.5] * count}
            frame["o"] = {"x": [0.5] * count, "y": [0.5] * count}
        frames.append(frame)
    return {"a": 1, "k": frames}


def sample(loop, step, function):
    """Sample a cyclic function so the first and last keyframe match exactly."""
    keys = [(t, function(t / loop)) for t in range(0, loop, step)]
    keys.append((loop, function(0.0)))
    return keys


def transform(position=None, opacity=100, rotation=0, scale=None, anchor=None):
    return {
        "o": opacity if isinstance(opacity, dict) else static(opacity),
        "r": rotation if isinstance(rotation, dict) else static(rotation),
        "p": position if isinstance(position, dict) else static(position or [0, 0]),
        "a": anchor if isinstance(anchor, dict) else static(anchor or [0, 0]),
        "s": scale if isinstance(scale, dict) else static(scale or [100, 100]),
    }


def group(items):
    return {"ty": "gr", "nm": "group", "bm": 0, "hd": False, "it": items + [{
        "ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]),
        "r": static(0), "o": static(100), "sk": static(0), "sa": static(0), "nm": "transform"}]}


def ellipse(size, color, opacity=100, position=(0, 0)):
    return group([
        {"ty": "el", "d": 1, "s": static(list(size)), "p": static(list(position)), "nm": "ellipse"},
        {"ty": "fl", "c": static(color), "o": static(opacity), "r": 1, "bm": 0, "nm": "fill"},
    ])


def path(vertices, color, width, closed=False):
    shape = {"i": [[0, 0]] * len(vertices), "o": [[0, 0]] * len(vertices),
             "v": [list(v) for v in vertices], "c": closed}
    return group([
        {"ty": "sh", "d": 1, "ks": static(shape), "nm": "path"},
        {"ty": "st", "c": static(color), "o": static(100), "w": static(width),
         "lc": 2, "lj": 2, "bm": 0, "nm": "stroke"},
    ])


def morphing_path(keys, color, width):
    """keys: (frame, vertices). Vertex counts must match across keyframes."""
    def shape_of(vertices):
        return {"i": [[0, 0]] * len(vertices), "o": [[0, 0]] * len(vertices),
                "v": [list(v) for v in vertices], "c": False}
    frames = []
    for index, (time, vertices) in enumerate(keys):
        frame = {"t": round(time), "s": [shape_of(vertices)]}
        if index < len(keys) - 1:
            frame["i"] = {"x": [0.5], "y": [0.5]}
            frame["o"] = {"x": [0.5], "y": [0.5]}
        frames.append(frame)
    return group([
        {"ty": "sh", "d": 1, "ks": {"a": 1, "k": frames}, "nm": "path"},
        {"ty": "st", "c": static(color), "o": static(100), "w": static(width),
         "lc": 2, "lj": 2, "bm": 0, "nm": "stroke"},
    ])


def rectangle(size, color, opacity=100, position=(0, 0), roundness=0):
    return group([
        {"ty": "rc", "d": 1, "s": static(list(size)), "p": static(list(position)),
         "r": static(roundness), "nm": "rect"},
        {"ty": "fl", "c": static(color), "o": static(opacity), "r": 1, "bm": 0, "nm": "fill"},
    ])


def layer(index, name, shapes, ks, loop):
    return {"ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1, "ks": ks, "ao": 0,
            "shapes": shapes, "ip": 0, "op": loop, "st": 0, "bm": 0}


def composition(name, layers, loop):
    return {"v": "5.7.4", "fr": FR, "ip": 0, "op": loop, "w": W, "h": H,
            "nm": name, "ddd": 0, "assets": [], "layers": layers, "markers": []}


def noise(index, salt):
    value = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
    return value - math.floor(value)


def orchard():
    """Petals falling through the moonlight, turning as they go."""
    loop = 900
    layers = []
    for i in range(16):
        seed_x, seed_y, seed_r = noise(i, 1), noise(i, 2), noise(i, 3)
        start = seed_y
        drift = 90 + seed_x * 150
        base_x = 40 + seed_x * (W - 80)
        spin = (1 if seed_r > 0.5 else -1) * (1 + round(seed_r * 2))

        def position(p, start=start, base_x=base_x, drift=drift, seed_x=seed_x):
            cycle = (p + start) % 1.0
            x = base_x + math.sin(cycle * math.pi * 4 + seed_x * 6.28) * drift
            return [x, -150 + cycle * (H + 300)]

        def opacity(p, start=start):
            cycle = (p + start) % 1.0
            # Fade in as it enters and out before it leaves, so the loop never pops.
            return round(min(1.0, cycle / 0.12, (1.0 - cycle) / 0.12) * 62)

        size = 16 + seed_x * 16
        layers.append(layer(
            len(layers) + 1, f"petal-{i}",
            [ellipse((size * 2.1, size), rgba(0xE8C6C9))],
            transform(position=animated(sample(loop, 10, position)),
                      opacity=animated(sample(loop, 30, opacity)),
                      rotation=animated([(0, 0), (loop, 360 * spin)])),
            loop))
    return composition("orchard", layers, loop)


def chamber():
    """A candle flame that never repeats the same shape twice in a breath."""
    loop = 600
    flame_x, flame_y = W * 0.72, H * 0.395
    layers = []

    def flicker(p):
        angle = p * math.pi * 2
        return (math.sin(angle * 7) * 0.3 + math.sin(angle * 11) * 0.22
                + math.sin(angle * 23) * 0.12)

    # Two glow shells breathe with the flame; stacked alpha stands in for a blur.
    for index, (radius, alpha, spread) in enumerate([(520, 16, 0.5), (300, 22, 0.8)]):
        layers.append(layer(
            len(layers) + 1, f"glow-{index}",
            [ellipse((radius, radius * 0.92), rgba(0xFFC27A), alpha)],
            transform(position=[flame_x, flame_y],
                      scale=animated(sample(loop, 4, lambda p, s=spread: (
                          [100 + flicker(p) * 9 * s, 100 + flicker(p) * 7 * s])))),
            loop))

    flame_keys = []
    for t in range(0, loop, 2):
        f = flicker(t / loop)
        flame_keys.append((t, [
            [flame_x + f * 5, flame_y - 96 - f * 30],
            [flame_x + 26 - f * 3, flame_y - 20],
            [flame_x, flame_y + 18],
            [flame_x - 26 - f * 3, flame_y - 20],
        ]))
    flame_keys.append((loop, flame_keys[0][1]))
    layers.append(layer(len(layers) + 1, "flame",
                        [morphing_path(flame_keys, rgba(0xFFD88A), 26)],
                        transform(), loop))
    layers.append(layer(
        len(layers) + 1, "core",
        [ellipse((22, 46), rgba(0xFFF3D2))],
        transform(position=animated(sample(loop, 4, lambda p: (
                      [flame_x + flicker(p) * 3, flame_y - 26 - flicker(p) * 8]))),
                  scale=animated(sample(loop, 4, lambda p: (
                      [100, 100 + flicker(p) * 18])))),
        loop))
    return composition("chamber", layers, loop)


def tomb():
    """A shaft of light that breathes, and mist that crawls across the stone."""
    loop = 1200
    layers = []
    layers.append(layer(
        len(layers) + 1, "shaft",
        [group([
            {"ty": "sh", "d": 1, "ks": static({
                "i": [[0, 0]] * 4, "o": [[0, 0]] * 4,
                "v": [[W * 0.34, 0], [W * 0.58, 0], [W * 0.78, H * 0.72], [W * 0.4, H * 0.72]],
                "c": True}), "nm": "path"},
            {"ty": "fl", "c": static(rgba(0xB6BDD5)), "o": static(13), "r": 1, "bm": 0, "nm": "fill"},
        ])],
        transform(opacity=animated(sample(loop, 20, lambda p: round(
            58 + 42 * math.sin(p * math.pi * 2))))),
        loop))
    for i in range(4):
        offset = i / 4
        band_y = H * (0.68 + i * 0.05)

        def position(p, offset=offset, band_y=band_y):
            cycle = (p + offset) % 1.0
            return [-W * 0.4 + cycle * W * 1.8, band_y]

        layers.append(layer(
            len(layers) + 1, f"mist-{i}",
            [ellipse((W * 0.95, H * 0.075), rgba(0x9AA3BC), 11)],
            transform(position=animated(sample(loop, 20, position)),
                      opacity=animated(sample(loop, 30, lambda p, o=offset: round(
                          min(1.0, ((p + o) % 1.0) / 0.2, (1.0 - ((p + o) % 1.0)) / 0.2) * 100)))),
            loop))
    return composition("tomb", layers, loop)


def road():
    """Birds crossing the dawn, wings beating, never quite in step."""
    loop = 1800
    layers = []
    for i in range(3):
        offset = i / 45 + i * 0.3
        band_y = H * (0.1 + noise(i, 5) * 0.14)
        span = 34 + i * 7
        crossing = 0.34  # Each bird is only on screen for part of the cycle.

        def wings(p, span=span):
            beat = math.sin(p * math.pi * 2 * 34) * span * 0.75
            return [[-span * 2, beat * 0.25], [-span, -beat], [0, 0],
                    [span, -beat], [span * 2, beat * 0.25]]

        wing_keys = [(t, wings(t / loop)) for t in range(0, loop, 3)]
        wing_keys.append((loop, wings(0.0)))

        def position(p, offset=offset, band_y=band_y, crossing=crossing):
            cycle = (p + offset) % 1.0
            travel = min(1.0, cycle / crossing)
            return [-W * 0.2 + travel * W * 1.4,
                    band_y + math.sin(cycle * math.pi * 6) * H * 0.012]

        def opacity(p, offset=offset, crossing=crossing):
            cycle = (p + offset) % 1.0
            if cycle > crossing:
                return 0
            return round(min(1.0, cycle / 0.03, (crossing - cycle) / 0.03) * 70)

        layers.append(layer(
            len(layers) + 1, f"bird-{i}",
            [morphing_path(wing_keys, rgba(0x3C3040), 7)],
            transform(position=animated(sample(loop, 6, position)),
                      opacity=animated(sample(loop, 6, opacity))),
            loop))
    for i in range(4):
        offset = i / 4
        band_y = H * (0.5 + i * 0.06)

        def position(p, offset=offset, band_y=band_y):
            return [-W * 0.4 + ((p + offset) % 1.0) * W * 1.8, band_y]

        layers.append(layer(
            len(layers) + 1, f"mist-{i}",
            [ellipse((W * 1.0, H * 0.07), rgba(0xFFE2CB), 14)],
            transform(position=animated(sample(loop, 24, position)),
                      opacity=animated(sample(loop, 30, lambda p, o=offset: round(
                          min(1.0, ((p + o) % 1.0) / 0.2, (1.0 - ((p + o) % 1.0)) / 0.2) * 100)))),
            loop))
    return composition("road", layers, loop)


def letter():
    """The Friar's letter, for the moment the story asks 'what if'."""
    loop = 420
    cx, cy = W / 2, H / 2
    paper = rgba(0xF3E4D2)
    layers = [layer(
        1, "glow", [ellipse((760, 760), rgba(0xFFD9B0), 12)],
        transform(position=[cx, cy],
                  scale=animated(sample(loop, 10, lambda p: (
                      [92 + 12 * math.sin(p * math.pi * 2), 92 + 12 * math.sin(p * math.pi * 2)])))),
        loop)]

    # The sheet rises out of the envelope and settles.
    def sheet_position(p):
        lift = math.sin(min(1.0, p * 2.2) * math.pi / 2) if p < 0.45 else 1.0
        if p > 0.82:
            lift = 1.0 - (p - 0.82) / 0.18
        return [cx, cy - 40 - lift * 150]

    layers.append(layer(
        2, "sheet", [rectangle((360, 250), paper, 100, (0, 0), 10)],
        transform(position=animated(sample(loop, 6, sheet_position)),
                  opacity=animated(sample(loop, 12, lambda p: round(
                      min(1.0, p / 0.12, (1.0 - p) / 0.12) * 100))),
                  rotation=animated(sample(loop, 12, lambda p: (
                      math.sin(p * math.pi * 2) * 2.5)))),
        loop))
    for i in range(4):
        layers.append(layer(
            3 + i, f"line-{i}",
            [rectangle((200 - i * 22, 9), rgba(0x8C6A62), 70, (0, 0), 4)],
            transform(position=animated(sample(loop, 6, lambda p, i=i: (
                          [sheet_position(p)[0] - 40, sheet_position(p)[1] - 60 + i * 42]))),
                      opacity=animated(sample(loop, 12, lambda p, i=i: round(
                          min(1.0, max(0.0, p - 0.1 - i * 0.05) / 0.1,
                              (1.0 - p) / 0.12) * 100)))),
            loop))
    layers.append(layer(
        7, "envelope", [rectangle((400, 250), rgba(0xD9C3AE), 100, (0, 0), 8)],
        transform(position=[cx, cy + 90],
                  rotation=animated(sample(loop, 12, lambda p: (
                      math.sin(p * math.pi * 2) * 1.5)))),
        loop))
    layers.append(layer(
        8, "seal", [ellipse((74, 74), rgba(0x9D4057))],
        transform(position=[cx, cy + 90],
                  scale=animated(sample(loop, 10, lambda p: (
                      [100 + 6 * math.sin(p * math.pi * 2), 100 + 6 * math.sin(p * math.pi * 2)])))),
        loop))
    return composition("letter", layers, loop)


def thought():
    """Rings blooming outward under a decision, as a thought arrives."""
    loop = 480
    cx, cy = W / 2, H / 2
    layers = []
    for i in range(3):
        offset = i / 3

        def scale(p, offset=offset):
            cycle = (p + offset) % 1.0
            value = 30 + cycle * 150
            return [value, value]

        def opacity(p, offset=offset):
            cycle = (p + offset) % 1.0
            return round(min(1.0, cycle / 0.15) * (1.0 - cycle) * 46)

        layers.append(layer(
            len(layers) + 1, f"ring-{i}",
            [group([
                {"ty": "el", "d": 1, "s": static([520, 520]), "p": static([0, 0]), "nm": "ellipse"},
                {"ty": "st", "c": static(rgba(0xF0DAD8)), "o": static(100), "w": static(5),
                 "lc": 2, "lj": 2, "bm": 0, "nm": "stroke"},
            ])],
            transform(position=[cx, cy],
                      scale=animated(sample(loop, 8, scale)),
                      opacity=animated(sample(loop, 8, opacity))),
            loop))
    return composition("thought", layers, loop)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    animations = {"scene-orchard": orchard(), "scene-chamber": chamber(),
                  "scene-tomb": tomb(), "scene-road": road(),
                  "accent-letter": letter(), "accent-thought": thought()}
    for name, animation in animations.items():
        destination = OUTPUT / (name + ".json")
        destination.write_text(json.dumps(animation, separators=(",", ":")) + "\n")
        size = destination.stat().st_size / 1024
        seconds = animation["op"] / FR
        print(f"{name}: {len(animation['layers'])} layers, {seconds:.0f}s loop, {size:.0f} KB")
    print("Run python3 Scripts/create_project.py to bundle these with the app.")


if __name__ == "__main__":
    main()
