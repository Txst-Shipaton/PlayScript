#!/usr/bin/env python3
"""Build reusable vector assets from a video: characters and backgrounds, separately.

Nothing here is a frame sequence. Each asset is one still, clean vector that can
be placed, moved, and animated later on any background.

Pipeline, on Vertex AI:
1. One keyframe per scene: the middle of each scene in the framing analysis.
2. Segmentation agents (Gemini) find every character in each keyframe, labelled
   with the entity ids from the character analysis, and return pixel masks.
3. Each character's clearest appearance is cut out on transparency, edges
   smoothed, and traced into a standalone SVG anchored at the feet.
4. Inpainting agents (Gemini image model) remove the characters from each keyframe, and the
   clean plate is traced into a background SVG.
A composer page lets you drag any character over any background.

Output is a copy of third-party footage and goes to analysis/<video>/assets/,
which git ignores.

  python3 Scripts/vector_assets.py --only S1,S5     # a few scenes first
  python3 Scripts/vector_assets.py                  # every scene
"""
import argparse
import base64
import html
import io
import json
import re
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import vtracer
from PIL import Image, ImageFilter

from create_narration import ROOT, environment
from trace_video import ASSETS, DETAIL
from video_agents import Vertex, text_of

SEGMENTER = "gemini-2.5-flash"
# Imagen editing is not available on this project; Gemini's image model edits by instruction.
INPAINTER = "gemini-2.5-flash-image"
UPSCALE = 3  # Tracing an upscaled cutout gives smoother curves than the 360p source.
MAX_COVERAGE = 0.35  # Above this, a close-up leaves too little real set to rebuild a background.
# The image model has a tight per-minute quota; a few calls at a time avoids 429 failures.
PAINT_SLOTS = threading.Semaphore(3)
# Mean colour change (0-255) outside the removed area above which a background was redrawn, not repaired.
FAITHFUL_LIMIT = 18


def keyframe(video, ms, destination):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{ms / 1000:.3f}", "-i", str(video),
                    "-frames:v", "1", str(destination)], check=True)
    return Image.open(destination).convert("RGB")


def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


def segment(gemini, frame, characters):
    known = "\n".join(f"- {c['entity_id']}: {json.dumps({k: v for k, v in c.items() if k != 'entity_id'})}"
                      for c in characters)
    prompt = (
        "Segment every character visible in this film frame, including figures partly outside "
        "the frame or seen from behind.\n"
        f"Known characters, with their analysed appearance; label a figure with the matching id:\n{known}\n"
        'Label any other person "unknown". Output a JSON list. Each entry has "label", "box_2d" as '
        '[y0, x0, y1, x1] normalised to 0-1000, "mask" as a base64 PNG probability map of that box, '
        'and "full_body" true only if the whole figure is inside the frame and unobstructed.')
    body = {"contents": [{"role": "user", "parts": [
                {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(png_bytes(frame)).decode()}},
                {"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0.1,
                                 # Segmentation is more precise without a thinking pass.
                                 "thinkingConfig": {"thinkingBudget": 0}}}
    items = json.loads(text_of(gemini.generate(body)))
    known_ids = {c["entity_id"] for c in characters}
    width, height = frame.size
    figures = []
    for item in items if isinstance(items, list) else []:
        try:
            y0, x0, y1, x1 = item["box_2d"]
        except (KeyError, ValueError, TypeError):
            continue
        left, top = max(0, int(x0 / 1000 * width)), max(0, int(y0 / 1000 * height))
        right, bottom = min(width, int(x1 / 1000 * width)), min(height, int(y1 / 1000 * height))
        if right - left < 12 or bottom - top < 12:
            continue
        mask = Image.new("L", frame.size, 0)
        try:
            probability = Image.open(io.BytesIO(base64.b64decode(str(item["mask"]).split(",", 1)[-1]))).convert("L")
            mask.paste(probability.resize((right - left, bottom - top), Image.BILINEAR)
                       .point(lambda v: 255 if v > 127 else 0), (left, top))
            inside = mask.crop((left, top, right, bottom)).histogram()[255] / ((right - left) * (bottom - top))
            # A mask that nearly fills its box is the box, not a figure: fine for removal, useless for a cutout.
            mask_ok = inside < 0.85
        except (KeyError, ValueError, TypeError, OSError):
            # Close-ups can come back with a box but no usable mask. The box still tells the
            # inpainter what to remove; it is just too rough to cut a character from.
            mask.paste(255, (left, top, right, bottom))
            mask_ok = False
        label = str(item.get("label", "unknown")).strip().lower()
        figures.append({"label": label if label in known_ids else "unknown", "box": (left, top, right, bottom),
                        "mask": mask, "mask_ok": mask_ok, "area": mask.histogram()[255],
                        "full_body": bool(item.get("full_body")),
                        # Objective, unlike the model's own full_body flag: the figure is not cropped by the frame.
                        "inside_frame": left > 2 and top > 2 and right < width - 2 and bottom < height - 2})
    return figures


def trace(png_path, svg_path, group_id, detail, origin):
    raw = svg_path.with_suffix(".raw.svg")
    vtracer.convert_image_to_svg_py(str(png_path), str(raw), colormode="color", hierarchical="stacked",
                                    mode="spline", corner_threshold=60, length_threshold=4.0,
                                    max_iterations=10, splice_threshold=45, path_precision=2,
                                    **DETAIL[detail])
    body = raw.read_text()
    raw.unlink()
    size = re.search(r'width="(\d+)"\s+height="(\d+)"', body)
    inner = body[body.find(">", body.find("<svg")) + 1:body.rfind("</svg>")].strip()
    width, height = size.group(1), size.group(2)
    svg_path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">\n'
        f'<g id="{group_id}" style="transform-box:fill-box;transform-origin:{origin}">\n{inner}\n</g>\n</svg>\n')


def cutout(frame, figure):
    """The figure alone on transparency, upscaled, with a smoothed hard edge."""
    left, top, right, bottom = figure["box"]
    size = ((right - left) * UPSCALE, (bottom - top) * UPSCALE)
    colour = frame.crop(figure["box"]).resize(size, Image.LANCZOS).convert("RGBA")
    edge = (figure["mask"].crop(figure["box"]).resize(size, Image.LANCZOS)
            .filter(ImageFilter.GaussianBlur(UPSCALE * 0.8)).point(lambda v: 255 if v > 127 else 0))
    colour.putalpha(edge)
    return colour


def union_mask(size, figures):
    union = Image.new("L", size, 0)
    for figure in figures:
        union.paste(255, mask=figure["mask"])
    return union


def magenta_left(image):
    small = image.resize((160, 90))
    return sum(1 for r, g, b in small.getdata() if r > 200 and g < 70 and b > 200) / (160 * 90)


def outside_change(frame, plate, region):
    """Mean colour change outside the removed area: low means the set was kept, high means redrawn."""
    size = (160, 90)
    before, after = frame.resize(size).getdata(), plate.resize(size).getdata()
    kept = [value == 0 for value in region.resize(size).getdata()]
    changes = [sum(abs(x - y) for x, y in zip(a, b)) / 3 for a, b, keep in zip(before, after, kept) if keep]
    return round(sum(changes) / len(changes), 1) if changes else 0.0


def clean_plate(painter, gemini, frame, figures, characters):
    """Characters removed from the frame, verified by segmenting the result again."""
    # Grow the region past soft edges and motion blur, so no outline ghost survives, then
    # paint it solid magenta: an instruction editor cannot miss or reinterpret that.
    region = union_mask(frame.size, figures).filter(ImageFilter.MaxFilter(9))
    marked = frame.copy()
    marked.paste((255, 0, 255), mask=region)
    problem = "no attempt made"
    for attempt in range(2):
        body = {"contents": [{"role": "user", "parts": [
                    {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(png_bytes(marked)).decode()}},
                    {"text": "This is a frame from an animated film with a solid magenta area. Replace the entire "
                             "magenta area with what would be behind it in this set: continue the walls, wallpaper "
                             "pattern, furniture, doorways and floor, matching the lighting, perspective, colours "
                             "and rendering style exactly. There must be no people or characters anywhere in the "
                             "result, including at the edges of the frame. Leave everything outside the magenta "
                             "area unchanged and keep the same framing. Return only the edited image."}]}],
                "generationConfig": {"responseModalities": ["IMAGE"], "temperature": 0.2 + attempt * 0.4}}
        with PAINT_SLOTS:
            response = painter.generate(body)
        parts = response.get("candidates", [{}])[0].get("content", {}).get("parts", [])
        data = next((part["inlineData"]["data"] for part in parts if "inlineData" in part), None)
        if not data:
            problem = "the image model returned no image (often a safety filter)"
            continue
        plate = Image.open(io.BytesIO(base64.b64decode(data))).convert("RGB")
        if magenta_left(plate) > 0.005:
            problem = "magenta was left unfilled"
            continue
        leftover = [f for f in segment(gemini, plate, characters) if f["area"] > 0.01 * plate.width * plate.height]
        if not leftover:
            return plate, outside_change(frame, plate, region)
        problem = "characters still visible after removal: " + ", ".join(sorted({f["label"] for f in leftover}))
    raise RuntimeError(problem)


def composer(out, characters, backgrounds):
    options = "".join(f'<option value="backgrounds/{html.escape(b)}">{html.escape(b)}</option>' for b in backgrounds)
    palette = "".join(f'<button data-src="characters/{html.escape(c)}">{html.escape(Path(c).stem)}</button>'
                      for c in characters)
    (out / "composer.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Vector asset composer</title><style>"
        "body{font:14px system-ui;background:#111;color:#ddd;margin:20px}"
        "#stage{position:relative;width:min(100%,1100px);aspect-ratio:16/9;overflow:hidden;background:#000}"
        "#bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}"
        ".c{position:absolute;height:45%;cursor:grab;user-select:none;transform-origin:50% 100%}"
        "button,select{margin:4px;padding:6px 10px;background:#222;color:#ddd;border:1px solid #444;border-radius:6px}"
        "</style><p>Background <select id=pick>" + options + "</select> "
        "Add character " + palette + " <span>(drag to move, scroll to resize, double-click to remove)</span></p>"
        "<div id=stage><img id=bg></div><script>"
        "const stage=document.getElementById('stage'),bg=document.getElementById('bg'),pick=document.getElementById('pick');"
        "const show=()=>bg.src=pick.value;pick.onchange=show;show();"
        "document.querySelectorAll('button[data-src]').forEach(b=>b.onclick=()=>{"
        "const c=document.createElement('img');c.src=b.dataset.src;c.className='c';c.style.left='40%';c.style.top='40%';"
        "c.draggable=false;stage.appendChild(c);});"
        "let drag=null;stage.addEventListener('pointerdown',e=>{if(!e.target.classList.contains('c'))return;"
        "const r=e.target.getBoundingClientRect();drag={el:e.target,dx:e.clientX-r.left,dy:e.clientY-r.top};"
        "e.target.setPointerCapture(e.pointerId);});"
        "stage.addEventListener('pointermove',e=>{if(!drag)return;const s=stage.getBoundingClientRect();"
        "drag.el.style.left=(e.clientX-s.left-drag.dx)/s.width*100+'%';drag.el.style.top=(e.clientY-s.top-drag.dy)/s.height*100+'%';});"
        "stage.addEventListener('pointerup',()=>drag=null);"
        "stage.addEventListener('wheel',e=>{if(!e.target.classList.contains('c'))return;e.preventDefault();"
        "const h=parseFloat(e.target.style.height||45);e.target.style.height=Math.max(5,h-e.deltaY*0.05)+'%';},{passive:false});"
        "stage.addEventListener('dblclick',e=>{if(e.target.classList.contains('c'))e.target.remove();});"
        "</script>\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--only", help="comma-separated scene ids")
    parser.add_argument("--workers", type=int, default=24)
    parser.add_argument("--detail", choices=DETAIL, default="high")
    args = parser.parse_args()
    env = environment()

    video = args.video or next(ASSETS.glob("*.mp4"), None)
    if not video or not video.exists():
        raise SystemExit("No video found; pass --video.")
    stem = re.sub(r"[^A-Za-z0-9_-]+", "-", video.stem).strip("-")[:60]
    master = json.loads((ROOT / "analysis" / stem / "master_state.json").read_text())
    scenes = master["agents"]["framing_analyst"]["scenes"]
    characters = master["agents"]["character_morphologist"]["entities"]
    if args.only:
        wanted = set(args.only.split(","))
        scenes = [s for s in scenes if s["scene_id"] in wanted]

    out = ROOT / "analysis" / stem / "assets"
    for folder in ("keyframes", "characters", "backgrounds"):
        (out / folder).mkdir(parents=True, exist_ok=True)

    gemini = Vertex(env, SEGMENTER, "global")
    painter = Vertex(env, INPAINTER, "global")
    print(f"{len(scenes)} scenes; segmentation {SEGMENTER}, inpainting {INPAINTER}, via {gemini.mode}", flush=True)

    lock = threading.Lock()
    appearances, backgrounds, failures, skipped = [], [], {}, {}

    def scene_job(scene):
        scene_id = scene["scene_id"]
        try:
            middle = (scene["start_ms"] + scene["end_ms"]) / 2
            frame = keyframe(video, middle, out / "keyframes" / f"{scene_id}.png")
            figures = segment(gemini, frame, characters)
            with lock:
                appearances.extend(dict(f, scene_id=scene_id, frame=frame) for f in figures if f["label"] != "unknown" and f["mask_ok"])
            coverage = union_mask(frame.size, figures).histogram()[255] / (frame.width * frame.height)
            if coverage > MAX_COVERAGE:
                skipped[scene_id] = f"close-up: characters cover {coverage:.0%} of the frame"
                print(f"  skip   {scene_id}: {skipped[scene_id]}", flush=True)
                return
            plate, drift = clean_plate(painter, gemini, frame, figures, characters) if figures else (frame, 0.0)
            plate_path = out / "keyframes" / f"{scene_id}-clean.png"
            plate.save(plate_path)
            trace(plate_path, out / "backgrounds" / f"{scene_id}.svg", f"background_{scene_id}", args.detail, "50% 50%")
            with lock:
                backgrounds.append({"scene_id": scene_id, "file": f"{scene_id}.svg",
                                    "characters_removed": [f["label"] for f in figures],
                                    "outside_change": drift, "faithful": drift < FAITHFUL_LIMIT})
            note = "" if drift < FAITHFUL_LIMIT else " -- REDRAWN, set does not match the video"
            print(f"  scene  {scene_id}: {len(figures)} figure(s) removed, set change {drift}{note}", flush=True)
        except (RuntimeError, ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
            failures[scene_id] = str(error)
            print(f"  failed {scene_id}: {error}", flush=True)

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        list(pool.map(scene_job, scenes))

    # A character asset must be the whole figure, clear of the frame edges. A character never seen
    # that way is reported, not shipped cropped or with background attached.
    best = {}
    for figure in appearances:
        if not figure["inside_frame"]:
            continue
        current = best.get(figure["label"])
        if current is None or figure["area"] > current["area"]:
            best[figure["label"]] = figure
    unseen = sorted({f["label"] for f in appearances} - set(best))
    character_files = {}
    for label, figure in sorted(best.items()):
        png = out / "keyframes" / f"character-{label}.png"
        cutout(figure["frame"], figure).save(png)
        trace(png, out / "characters" / f"{label}.svg", label, args.detail, "50% 100%")
        character_files[label] = {"file": f"{label}.svg", "from_scene": figure["scene_id"],
                                  "full_body": figure["full_body"]}
        print(f"  character {label} (from {figure['scene_id']})", flush=True)

    backgrounds.sort(key=lambda b: [int(n) if n.isdigit() else n for n in re.split(r"(\d+)", b["scene_id"])])
    (out / "manifest.json").write_text(json.dumps({"source_video": video.name, "characters": character_files,
                                                   "backgrounds": backgrounds, "skipped": skipped, "failed": failures,
                                                   "characters_without_clean_appearance": unseen}, indent=2) + "\n")
    composer(out, [c["file"] for c in character_files.values()], [b["file"] for b in backgrounds])
    print(f"{len(character_files)} characters, {len(backgrounds)}/{len(scenes)} backgrounds "
          f"({len(skipped)} close-ups skipped, {len(failures)} failed) -> "
          f"{(out / 'composer.html').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
