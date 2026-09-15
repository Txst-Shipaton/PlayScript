#!/usr/bin/env python3
"""Generate animated SVGs from the twelve-agent video analysis, with Gemini on Vertex AI.

Every SVG agent receives the complete master_state.json -- all twelve analysts'
output -- and one narrow assignment: a single scene, or a single character
sheet. Agents run in parallel. Each SVG is validated locally (well-formed XML,
no scripts, no external resources) and regenerated once with the problem named
if it fails. A gallery page and manifest are written alongside.

  python3 Scripts/svg_agents.py --only S1          # one scene, to check quality first
  python3 Scripts/svg_agents.py                    # every scene and character
"""
import argparse
import html
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from create_narration import ROOT, environment
from video_agents import Vertex, text_of

FALLBACK_MODEL = "gemini-2.5-flash"

DIRECTOR = """You are one SVG director in a multi-agent pipeline that rebuilds a video as animated vector art.

The MASTER STATE below is the complete output of twelve specialist analysts of the same video:
framing (scenes, timing, camera), colorist (palette, gradients), environment mapper
(background geometry, perspective), character morphologist (shapes, colours per part),
rigging analyst (group hierarchy, pivots), motion tracker (transforms, easing), lighting
(light direction, shadows), stroke inspector (line style), layer coordinator (render order),
FX generator (particles), typography parser (overlays), and keyframe synchronizer (timelines).

Use ALL of it that bears on your assignment. Cross-reference analysts by scene_id, entity_id
and target_id. Where analysts disagree, prefer the more specific one for that property.

Output rules -- follow every one:
- Return exactly one complete, self-contained SVG document and nothing else: no prose, no fences.
- Root: <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 720">. The source is 16:9.
- Animate with CSS @keyframes inside a <style> element in the SVG. No JavaScript, no <script>,
  no event attributes, no external fonts, images, or links of any kind.
- Gradients and filters in <defs>, using the colorist's exact hex values and the lighting
  analyst's shadow parameters.
- Draw in the layer coordinator's render order. Give groups the ids analysts use, and set
  transform-origin from the rigging analyst's pivot points on rigged groups.
- Map motion tracker and keyframe synchronizer data onto keyframe percentages of the scene's
  own duration; loop with animation-iteration-count: infinite. Camera moves from framing
  become a transform animation on one top-level camera group.
- Style: stylised flat vector illustration with depth from gradients and shadows. Characters
  are stylised figures, never a likeness of any real actor.
- Include text only where the typography parser records an overlay for this scene.
- Prefer fewer, well-shaped paths over many tiny ones; keep the file under about 60 KB.

MASTER STATE:
"""


def extract_svg(text):
    text = re.sub(r"^```(?:svg|xml)?\s*|\s*```$", "", text.strip())
    start, end = text.find("<svg"), text.rfind("</svg>")
    return text[start:end + len("</svg>")] if start != -1 and end != -1 else ""


def problems_with(svg):
    if not svg:
        return "no complete <svg>...</svg> document was returned"
    try:
        root = ET.fromstring(svg)
    except ET.ParseError as error:
        return f"the SVG is not well-formed XML ({error})"
    if not root.tag.endswith("svg"):
        return "the root element is not <svg>"
    if re.search(r"<script|\son[a-z]+\s*=", svg, re.I):
        return "it contains scripting, which is not allowed"
    if re.search(r"(?:href|src)\s*=\s*[\"']\s*(?:https?:|data:|//)", svg, re.I) or "@import" in svg:
        return "it references an external or embedded resource, which is not allowed"
    return None


def assignments(master):
    agents = master["agents"]
    jobs = []
    for scene in agents.get("framing_analyst", {}).get("scenes", []):
        jobs.append((f"scene-{scene['scene_id']}", scene["scene_id"],
                     "Your assignment: the animated SVG for scene "
                     f"{scene['scene_id']}. Its framing entry is:\n{json.dumps(scene)}\n"
                     "Compose the environment, characters present, lighting, FX and camera "
                     "motion for this scene only, looping over its duration."))
    for entity in agents.get("character_morphologist", {}).get("entities", []):
        entity_id = entity["entity_id"]
        jobs.append((f"character-{entity_id}", entity_id,
                     f"Your assignment: a character sheet SVG for entity {entity_id}. Its "
                     f"morphology is:\n{json.dumps(entity)}\nDraw the figure standing, centred, "
                     "on a plain background from the palette, built from the rigging analyst's "
                     "group hierarchy with correct pivots, and give it a subtle looping idle "
                     "animation drawn from the motion data recorded for this entity."))
    return jobs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--master", type=Path)
    parser.add_argument("--model")
    parser.add_argument("--location", default="global")
    parser.add_argument("--workers", type=int, default=24)
    parser.add_argument("--force", action="store_true", help="regenerate SVGs that already exist")
    parser.add_argument("--only", help="comma-separated scene or entity ids")
    args = parser.parse_args()
    env = environment()

    master_path = args.master or next(iter(sorted((ROOT / "analysis").glob("*/master_state.json"))), None)
    if not master_path or not master_path.exists():
        raise SystemExit("No master_state.json found; run Scripts/video_agents.py first.")
    master = json.loads(master_path.read_text())
    out = master_path.parent / "svg"
    out.mkdir(exist_ok=True)

    model = args.model or env.get("VERTEX_SVG_MODEL", "gemini-2.5-pro")
    vertex = Vertex(env, model, args.location)
    # One cheap call settles auth and whether the preferred model is available,
    # before dozens of parallel requests depend on it.
    try:
        vertex.generate({"contents": [{"role": "user", "parts": [{"text": "Reply OK."}]}]})
    except RuntimeError as error:
        if model == FALLBACK_MODEL:
            raise SystemExit(f"Vertex AI unavailable: {error}")
        print(f"{model} unavailable ({error}); using {FALLBACK_MODEL}.", flush=True)
        model = FALLBACK_MODEL
        vertex = Vertex(env, model, args.location)

    jobs = assignments(master)
    if args.only:
        wanted = set(args.only.split(","))
        jobs = [job for job in jobs if job[1] in wanted]
    if not args.force:
        # Resumable: a rerun only generates what is missing.
        existing = [job for job in jobs if (out / f"{job[0]}.svg").exists()]
        jobs = [job for job in jobs if job not in existing]
        if existing:
            print(f"Skipping {len(existing)} SVGs already on disk (--force to redo).", flush=True)
    system = DIRECTOR + json.dumps(master, separators=(",", ":"), ensure_ascii=False)
    print(f"{len(jobs)} SVG agents via {vertex.mode}, model {model}; "
          f"each given the full {len(system) // 1024} KB master state.", flush=True)

    def job(entry):
        name, subject, assignment = entry
        started = time.time()
        prompt = assignment
        for attempt in range(2):
            body = {"systemInstruction": {"parts": [{"text": system}]},
                    "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                    "generationConfig": {"temperature": 0.4, "maxOutputTokens": 32000}}
            try:
                svg = extract_svg(text_of(vertex.generate(body)))
            except (RuntimeError, KeyError, IndexError) as error:
                svg, problem = "", f"request failed: {error}"
            else:
                problem = problems_with(svg)
            if not problem:
                (out / f"{name}.svg").write_text(svg + "\n")
                print(f"  done   {name} ({len(svg) // 1024} KB, {time.time() - started:.0f}s)", flush=True)
                return True
            prompt = f"{assignment}\n\nYour previous answer was rejected because {problem}. Fix that."
        print(f"  failed {name}: {problem}", flush=True)
        return False

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        results = list(pool.map(job, jobs))

    # The gallery covers every SVG on disk, including ones from earlier runs.
    manifest = [{"file": path.name, "subject": path.stem.split("-", 1)[-1], "bytes": path.stat().st_size}
                for path in sorted(out.glob("*.svg"))]
    (out / "manifest.json").write_text(json.dumps({"model": model, "source": master_path.name,
                                                   "svgs": manifest}, indent=2) + "\n")
    cards = "\n".join(
        f'<figure><img src="{html.escape(item["file"])}" alt="{html.escape(item["subject"])}">'
        f'<figcaption>{html.escape(item["file"])}</figcaption></figure>' for item in manifest)
    (out / "index.html").write_text(
        "<!doctype html><meta charset=utf-8><title>SVG agents</title><style>"
        "body{font:14px system-ui;background:#111;color:#ddd;margin:24px}"
        "main{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:16px}"
        "img{width:100%;background:#000;border-radius:6px}figure{margin:0}</style>"
        f"<h1>{len(manifest)} generated SVGs</h1><main>{cards}</main>\n")
    print(f"{sum(results)}/{len(jobs)} SVGs -> {out.relative_to(ROOT)}/index.html")
    if not all(results):
        sys.exit(1)


if __name__ == "__main__":
    main()
