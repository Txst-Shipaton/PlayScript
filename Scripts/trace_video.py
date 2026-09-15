#!/usr/bin/env python3
"""Trace a video, frame by frame, into one self-contained animated SVG.

Each frame is extracted with ffmpeg and vectorised by vtracer, so the result
looks like the footage itself rather than an interpretation of it. The frames
are stacked as groups and flipped with CSS, one visible at a time. A side-by-
side page compares the SVG against the original segment.

Output is large and is a copy of the source footage; it is written under
analysis/<video>/trace/, which git ignores.

  python3 Scripts/trace_video.py --start 20 --duration 3        # short proof
  python3 Scripts/trace_video.py --fps 8 --detail low           # whole video, smaller file
"""
import argparse
import html
import os
import re
import subprocess
import tempfile
from pathlib import Path

import vtracer

from create_narration import ROOT

ASSETS = ROOT / "PlayScript/Resources/Assets.xcassets"
# Higher detail keeps more colours and smaller shapes, at a steep cost in size.
DETAIL = {
    "high": {"filter_speckle": 4, "color_precision": 7, "layer_difference": 12},
    "medium": {"filter_speckle": 6, "color_precision": 6, "layer_difference": 20},
    "low": {"filter_speckle": 10, "color_precision": 5, "layer_difference": 32},
}


def trace_frame(png, settings):
    svg_path = png.with_suffix(".svg")
    vtracer.convert_image_to_svg_py(str(png), str(svg_path), colormode="color",
                                    hierarchical="stacked", mode="spline",
                                    corner_threshold=60, length_threshold=4.0,
                                    max_iterations=10, splice_threshold=45,
                                    path_precision=3, **settings)
    body = svg_path.read_text()
    size = re.search(r'width="(\d+)"\s+height="(\d+)"', body)
    inner = body[body.find(">", body.find("<svg")) + 1:body.rfind("</svg>")]
    return inner.strip(), (int(size.group(1)), int(size.group(2)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--duration", type=float, help="seconds; default to the end")
    parser.add_argument("--fps", type=float, default=12)
    parser.add_argument("--detail", choices=DETAIL, default="medium")
    args = parser.parse_args()

    video = args.video or next(ASSETS.glob("*.mp4"), None)
    if not video or not video.exists():
        raise SystemExit("No video found; pass --video.")
    stem = re.sub(r"[^A-Za-z0-9_-]+", "-", video.stem).strip("-")[:60]
    out = ROOT / "analysis" / stem / "trace"
    out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as work:
        command = ["ffmpeg", "-v", "error", "-ss", str(args.start)]
        if args.duration:
            command += ["-t", str(args.duration)]
        command += ["-i", str(video), "-vf", f"fps={args.fps}", os.path.join(work, "f%05d.png")]
        subprocess.run(command, check=True)
        frames = sorted(Path(work).glob("f*.png"))
        if not frames:
            raise SystemExit("ffmpeg produced no frames; check --start and --duration.")
        print(f"Tracing {len(frames)} frames at {args.fps:g} fps, {args.detail} detail...", flush=True)

        traced, size = [], None
        for index, frame in enumerate(frames, 1):
            inner, size = trace_frame(frame, DETAIL[args.detail])
            traced.append(inner)
            if index % 12 == 0 or index == len(frames):
                print(f"  {index}/{len(frames)}", flush=True)

    width, height = size
    step = 1 / args.fps
    total = step * len(traced)
    visible = 100 / len(traced)
    groups = "\n".join(f'<g class="f" style="animation-delay:{i * step:.4f}s">{body}</g>'
                       for i, body in enumerate(traced))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">\n'
           f"<style>.f{{visibility:hidden;animation:frame {total:.4f}s infinite}}"
           f"@keyframes frame{{0%{{visibility:visible}}{visible:.4f}%,100%{{visibility:hidden}}}}</style>\n"
           f"{groups}\n</svg>\n")
    name = f"trace-{args.start:g}s-{(args.duration or total):g}s-{args.fps:g}fps-{args.detail}"
    svg_file = out / f"{name}.svg"
    svg_file.write_text(svg)

    source = os.path.relpath(video, out)
    (out / f"{name}.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Trace comparison</title><style>"
        "body{font:14px system-ui;background:#111;color:#ddd;margin:24px}"
        "main{display:grid;grid-template-columns:1fr 1fr;gap:16px}video,img{width:100%;background:#000}"
        "</style><main><figure><video src=\"" + html.escape(source) + "\" autoplay muted loop></video>"
        "<figcaption>Original</figcaption></figure>"
        f'<figure><img src="{html.escape(svg_file.name)}"><figcaption>Traced SVG</figcaption></figure>'
        "</main>"
        f"<script>const v=document.querySelector('video');v.addEventListener('loadedmetadata',()=>"
        f"{{v.currentTime={args.start};}});v.addEventListener('timeupdate',()=>{{if(v.currentTime>"
        f"{args.start + total:.3f})v.currentTime={args.start};}});</script>\n")
    print(f"{svg_file.stat().st_size / 2**20:.1f} MB -> {svg_file.relative_to(ROOT)}")
    print(f"Compare: {(out / (name + '.html')).relative_to(ROOT)}")


if __name__ == "__main__":
    main()
