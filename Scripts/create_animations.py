#!/usr/bin/env python3
"""Generate the ten lightweight, vector-only Lottie scene loops."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "PlayScript/Resources/Animations"
FPS = 30


def color(hex_value: str) -> list[float]:
    value = hex_value.lstrip("#")
    return [int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)] + [1]


def static(value):
    return {"a": 0, "k": value}


def animated(frames):
    keys = []
    for index, (time, value) in enumerate(frames):
        key = {"t": time, "s": value if isinstance(value, list) else [value]}
        if index + 1 < len(frames):
            next_value = frames[index + 1][1]
            key["e"] = next_value if isinstance(next_value, list) else [next_value]
        keys.append(key)
    return {"a": 1, "k": keys}


def transform(position, opacity=100, scale=(100, 100, 100), rotation=0):
    return {
        "o": opacity if isinstance(opacity, dict) else static(opacity),
        "r": rotation if isinstance(rotation, dict) else static(rotation),
        "p": position if isinstance(position, dict) else static([*position, 0]),
        "a": static([0, 0, 0]),
        "s": scale if isinstance(scale, dict) else static(list(scale)),
    }


def shape_layer(name, index, shapes, position, end, opacity=100, scale=(100, 100, 100), rotation=0):
    return {
        "ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1,
        "ks": transform(position, opacity, scale, rotation), "ao": 0,
        "shapes": shapes, "ip": 0, "op": end, "st": 0, "bm": 0,
    }


def ellipse(width, height, fill):
    return [
        {"ty": "el", "p": static([0, 0]), "s": static([width, height]), "nm": "Ellipse"},
        {"ty": "fl", "c": static(color(fill)), "o": static(100), "r": 1, "nm": "Fill"},
        {"ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]), "r": static(0), "o": static(100), "sk": static(0), "sa": static(0), "nm": "Transform"},
    ]


def rectangle(width, height, radius, fill):
    return [
        {"ty": "rc", "p": static([0, 0]), "s": static([width, height]), "r": static(radius), "nm": "Rectangle"},
        {"ty": "fl", "c": static(color(fill)), "o": static(100), "r": 1, "nm": "Fill"},
        {"ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]), "r": static(0), "o": static(100), "sk": static(0), "sa": static(0), "nm": "Transform"},
    ]


def background(hex_value, end):
    return {
        "ddd": 0, "ind": 1, "ty": 1, "nm": "Backdrop", "sr": 1,
        "ks": transform((215, 466)), "ao": 0, "sw": 430, "sh": 932,
        "sc": hex_value, "ip": 0, "op": end, "st": 0, "bm": 0,
    }


def pulse(frames, low=35, high=60):
    third = frames // 3
    return animated([(0, low), (third, high), (third * 2, low + 5), (frames, low)])


def drift(frames, start, finish, midpoint=None):
    points = [(0, [*start, 0])]
    if midpoint:
        points.append((frames // 2, [*midpoint, 0]))
    points.append((frames, [*finish, 0]))
    return animated(points)


def mote(name, index, frames, start, finish, fill, size=8, delay=0):
    opacity = animated([(0, 0), (delay + frames // 5, 58), (frames * 4 // 5, 42), (frames, 0)])
    return shape_layer(name, index, ellipse(size, size, fill), drift(frames, start, finish), frames, opacity)


def make_opening(frames):
    layers = [background("#4A303B", frames)]
    layers.append(shape_layer("Window glow", 2, rectangle(184, 360, 88, "#F5D1B5"), (215, 300), frames, pulse(frames, 24, 42)))
    layers.append(shape_layer("Candle halo", 3, ellipse(150, 190, "#F5C8AA"), (312, 540), frames, pulse(frames, 18, 38)))
    layers.append(shape_layer("Candle", 4, ellipse(18, 42, "#FFF1D5"), drift(frames, (312, 542), (312, 538), (309, 544)), frames, pulse(frames, 72, 100), scale=animated([(0, [92, 105, 100]), (frames // 2, [108, 92, 100]), (frames, [92, 105, 100])])))
    layers.append(shape_layer("Curtain left", 5, rectangle(118, 620, 45, "#7D4052"), drift(frames, (24, 325), (24, 325), (32, 325)), frames, 88, rotation=animated([(0, -2), (frames // 2, 2), (frames, -2)])))
    layers.append(shape_layer("Curtain right", 6, rectangle(118, 620, 45, "#7D4052"), drift(frames, (406, 325), (406, 325), (398, 325)), frames, 88, rotation=animated([(0, 2), (frames // 2, -2), (frames, 2)])))
    return layers


def make_balcony(frames):
    layers = [background("#51333F", frames)]
    layers.append(shape_layer("Moon", 2, ellipse(136, 136, "#F8DDD0"), drift(frames, (320, 165), (316, 164), (318, 160)), frames, pulse(frames, 44, 61)))
    layers.append(shape_layer("Balcony arch", 3, rectangle(258, 600, 125, "#A56070"), (215, 410), frames, 25))
    moth_path = animated([(0, [125, 250, 0]), (45, [165, 215, 0]), (90, [205, 255, 0]), (135, [160, 285, 0]), (frames, [125, 250, 0])])
    layers.append(shape_layer("Moth glow", 4, ellipse(30, 30, "#FFE8C8"), moth_path, frames, pulse(frames, 24, 62)))
    layers.append(shape_layer("Moth", 5, ellipse(8, 5, "#FFF5DE"), moth_path, frames, 90, rotation=animated([(0, -12), (90, 18), (frames, -12)])))
    return layers


def make_confession(frames):
    layers = [background("#70414D", frames)]
    layers.append(shape_layer("Warm bloom", 2, ellipse(500, 610, "#D68A8B"), (215, 330), frames, pulse(frames, 15, 29), scale=animated([(0, [92, 92, 100]), (frames // 2, [106, 106, 100]), (frames, [92, 92, 100])])))
    for i, (x, y, dx, size) in enumerate([(85, 730, 18, 7), (168, 650, -14, 10), (276, 760, 12, 6), (350, 600, -18, 9), (235, 510, 8, 5)]):
        layers.append(mote(f"Light mote {i + 1}", i + 3, frames, (x, y), (x + dx, y - 230), "#FFE2CE", size, i * 7))
    return layers


def make_vow(frames):
    layers = [background("#3F2B38", frames)]
    layers.append(shape_layer("Moon wash", 2, ellipse(420, 420, "#DCA9AC"), (215, 170), frames, pulse(frames, 8, 15)))
    stars = [(62, 145, 7), (126, 90, 5), (190, 178, 6), (265, 82, 7), (340, 150, 5), (382, 245, 6), (105, 280, 5), (294, 310, 6)]
    for i, (x, y, size) in enumerate(stars):
        opacity = animated([(0, 20), (frames // 3, 20 + (i % 3) * 18), (frames * 2 // 3, 72), (frames, 20)])
        layers.append(shape_layer(f"Star {i + 1}", i + 3, ellipse(size, size, "#FFE5D7"), (x, y), frames, opacity, scale=animated([(0, [85, 85, 100]), (frames // 2, [115, 115, 100]), (frames, [85, 85, 100])])))
    return layers


def make_letter(frames, unstable=False):
    layers = [background("#62413E" if not unstable else "#58363A", frames)]
    intensity = (20, 42) if not unstable else (12, 55)
    layers.append(shape_layer("Amber wash", 2, ellipse(520, 650, "#E7A36F"), (125, 430), frames, pulse(frames, *intensity)))
    layers.append(shape_layer("Candle flame", 3, ellipse(25, 62, "#FFE7B9"), drift(frames, (95, 570), (95, 568), (89 if unstable else 92, 576)), frames, pulse(frames, 64, 100), scale=animated([(0, [88, 108, 100]), (frames // 2, [112, 86, 100]), (frames, [88, 108, 100])])))
    for i, (x, y, dx) in enumerate([(155, 690, 28), (250, 745, -20), (335, 650, 16), (205, 585, -12)]):
        layers.append(mote(f"Incense {i + 1}", i + 4, frames, (x, y), (x + dx, y - 300), "#F6D3B5", 9 + i * 3, i * 10))
    return layers


def make_tomb(frames, suspended=False):
    layers = [background("#34313B", frames)]
    layers.append(shape_layer("Stone arch", 2, rectangle(310, 700, 150, "#756871"), (215, 430), frames, 18 if suspended else 26))
    layers.append(shape_layer("Pale opening", 3, ellipse(280, 420, "#D8C7C6"), (215, 210), frames, pulse(frames, 8, 13) if suspended else pulse(frames, 10, 18)))
    count = 1 if suspended else 5
    for i in range(count):
        x = 90 + i * 63
        y = 580 + (i % 3) * 80
        distance = 70 if suspended else 150
        layers.append(mote(f"Dust {i + 1}", i + 4, frames, (x, y), (x + 16, y - distance), "#E9D7D2", 6 + (i % 2) * 4, i * 8))
    return layers


def make_dawn(frames):
    layers = [background("#9B5D5A", frames)]
    layers.append(shape_layer("Sunrise", 2, ellipse(430, 430, "#F6C58F"), drift(frames, (215, 420), (215, 375)), frames, pulse(frames, 24, 42), scale=animated([(0, [92, 92, 100]), (frames, [108, 108, 100])])))
    layers.append(shape_layer("Horizon", 3, rectangle(520, 280, 130, "#D88B76"), (215, 790), frames, 48))
    for i, (x, y, dx) in enumerate([(65, 770, 12), (135, 690, -8), (220, 790, 15), (300, 720, -12), (370, 810, 8)]):
        layers.append(mote(f"Dawn mote {i + 1}", i + 4, frames, (x, y), (x + dx, y - 280), "#FFE5BB", 7 + i % 3, i * 6))
    return layers


def make_closing(frames):
    layers = [background("#784951", frames)]
    layers.append(shape_layer("Final glow", 2, ellipse(530, 680, "#E6A09A"), (215, 430), frames, pulse(frames, 15, 29), scale=animated([(0, [95, 95, 100]), (frames // 2, [104, 104, 100]), (frames, [95, 95, 100])])))
    for i, (x, y) in enumerate([(115, 620), (215, 720), (315, 610)]):
        layers.append(mote(f"Resting light {i + 1}", i + 3, frames, (x, y), (x + (i - 1) * 10, y - 100), "#FFE2D1", 8, i * 12))
    return layers


SCENES = {
    "opening": (6, make_opening),
    "balcony_choice": (6, make_balcony),
    "confession": (6, make_confession),
    "vow_choice": (6, make_vow),
    "the_letter": (6, lambda frames: make_letter(frames, False)),
    "vial_choice": (5, lambda frames: make_letter(frames, True)),
    "the_tomb": (8, lambda frames: make_tomb(frames, False)),
    "whatif_prompt": (8, lambda frames: make_tomb(frames, True)),
    "whatif": (6, make_dawn),
    "closing": (8, make_closing),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (seconds, maker) in SCENES.items():
        end = seconds * FPS
        document = {
            "v": "5.12.2", "fr": FPS, "ip": 0, "op": end,
            "w": 430, "h": 932, "nm": f"PlayScript — {name}",
            "ddd": 0, "assets": [], "layers": list(reversed(maker(end))), "markers": [],
        }
        path = OUT / f"{name}.json"
        path.write_text(json.dumps(document, separators=(",", ":")) + "\n")
        print(f"Wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
