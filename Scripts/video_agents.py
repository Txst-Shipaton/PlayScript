#!/usr/bin/env python3
"""Run the 12 specialist agents from jsonagents.md over a video with Gemini on Vertex AI.

Each agent gets the same video but its own narrow brief and JSON shape, so no
single call has to hold every detail. All agents fire in parallel; their outputs
are saved individually and merged into one master_state.json.

Auth: VERTEX_API_KEY (or GOOGLE_API_KEY) from .env uses the Vertex AI express
endpoint. Without a key, the gcloud CLI login is used instead
(`gcloud auth print-access-token` plus the configured project).

  python3 Scripts/video_agents.py --probe          # one tiny call: checks auth and model
  python3 Scripts/video_agents.py                  # all 12 agents
  python3 Scripts/video_agents.py --agents colorist,motion_tracker
"""
import argparse
import base64
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from create_narration import ROOT, environment

BRIEF = ROOT / "PlayScript/Resources/Assets.xcassets/jsonagents.md"
OUTPUT = ROOT / "analysis"
# Inline video is limited by request size; beyond this, upload to Cloud Storage instead.
INLINE_LIMIT = 15 * 1024 * 1024


def load_agents(brief_path):
    """Parse jsonagents.md so the brief stays the single source of truth."""
    text = brief_path.read_text().split("Orchestration Strategy")[0]
    agents = []
    decoder = json.JSONDecoder()
    for section in re.split(r"^\d+\.\s+", text, flags=re.M)[1:]:
        title = section.splitlines()[0].strip()
        role = re.search(r"Role:\s*(.+)", section)
        target = re.search(r"Extraction Target:\s*(.+)", section)
        start = section.find("{", section.find("JSON"))
        example, _ = decoder.raw_decode(section[start:])
        agents.append({"id": example["agent_id"], "title": title,
                       "role": role.group(1).strip() if role else "",
                       "target": target.group(1).strip() if target else "",
                       "example": example})
    if len(agents) != 12:
        raise SystemExit(f"Expected 12 agents in {brief_path.name}, parsed {len(agents)}.")
    return agents


def instruction(agent):
    return (
        f"You are the {agent['title']} in a pipeline that rebuilds a video as animated SVG.\n"
        f"Role: {agent['role']}\nExtraction target: {agent['target']}\n\n"
        "Watch the entire video. Report only what is actually visible; never invent content. "
        "Cover every scene, using real millisecond timestamps. Use exact hex colours and "
        "numeric values an SVG generator can use directly. Where the example has a single "
        "scene_id, return a list covering all scenes instead.\n"
        f'Return only JSON with "agent_id": "{agent["id"]}", following this shape, '
        "extending arrays as needed. Every value in the example is a placeholder showing "
        "structure only: never reuse its colours, ids, names or numbers; measure them "
        f"from the video.\n{json.dumps(agent['example'], indent=2)}"
    )


class Vertex:
    def __init__(self, env, model, location):
        self.model = model
        self.env = env
        self.location = location
        self.key = env.get("VERTEX_API_KEY") or env.get("GOOGLE_API_KEY")
        if self.key:
            self.url = f"https://aiplatform.googleapis.com/v1/publishers/google/models/{model}:generateContent"
            self.mode = "API key"
        else:
            self._use_gcloud()

    def _use_gcloud(self):
        project = self.env.get("GOOGLE_CLOUD_PROJECT") or self._gcloud("config", "get-value", "project")
        host = ("aiplatform.googleapis.com" if self.location == "global"
                else f"{self.location}-aiplatform.googleapis.com")
        self.url = (f"https://{host}/v1/projects/{project}/locations/{self.location}"
                    f"/publishers/google/models/{self.model}:generateContent")
        self.key = None
        self.mode = f"gcloud CLI ({project})"

    @staticmethod
    def _gcloud(*args):
        try:
            return subprocess.run(["gcloud", *args], capture_output=True, text=True, check=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            raise SystemExit("No VERTEX_API_KEY and gcloud is unavailable; run `gcloud auth login`.") from None

    def generate(self, body, attempts=4):
        data = json.dumps(body).encode()
        for attempt in range(attempts):
            headers = {"Content-Type": "application/json"}
            if self.key:
                headers["x-goog-api-key"] = self.key
            else:
                headers["Authorization"] = "Bearer " + self._gcloud("auth", "print-access-token")
            try:
                with urllib.request.urlopen(urllib.request.Request(self.url, data=data, headers=headers),
                                            timeout=600) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                # Report status only: provider bodies can echo request details.
                try:
                    status = json.load(error).get("error", {}).get("status", "UNKNOWN")
                except (ValueError, AttributeError):
                    status = "UNKNOWN"
                # A key restricted away from Vertex AI is refused outright; the CLI login may still work.
                if error.code == 403 and self.key:
                    print("  API key refused by Vertex AI; using the gcloud login instead.", flush=True)
                    self._use_gcloud()
                    continue
                if error.code in (429, 500, 502, 503, 504) and attempt < attempts - 1:
                    time.sleep(2 ** attempt * 3)
                    continue
                raise RuntimeError(f"HTTP {error.code} {status}") from None
            except urllib.error.URLError as error:
                if attempt < attempts - 1:
                    time.sleep(2 ** attempt * 3)
                    continue
                raise RuntimeError(f"network: {error.reason}") from None


def text_of(response):
    parts = response.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    return "".join(part.get("text", "") for part in parts)


def run_agent(vertex, agent, video_part):
    started = time.time()
    body = {
        "systemInstruction": {"parts": [{"text": instruction(agent)}]},
        "contents": [{"role": "user", "parts": [video_part, {"text": "Analyse this video for your role."}]}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
    }
    result = json.loads(text_of(vertex.generate(body)))
    return result, time.time() - started


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--model")
    parser.add_argument("--location", default="global")
    parser.add_argument("--agents", help="comma-separated agent ids; default all 12")
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    env = environment()
    model = args.model or env.get("VERTEX_MODEL", "gemini-2.5-flash")
    vertex = Vertex(env, model, args.location)

    if args.probe:
        reply = text_of(vertex.generate({"contents": [{"role": "user", "parts": [{"text": "Reply with OK."}]}]}))
        print(f"Auth via {vertex.mode}; model {model} replied: {reply.strip()[:40]}")
        return

    video = args.video or next(BRIEF.parent.glob("*.mp4"), None)
    if not video or not video.exists():
        raise SystemExit("No video found; pass --video.")
    if video.stat().st_size > INLINE_LIMIT:
        raise SystemExit(f"{video.name} is over {INLINE_LIMIT // 2**20} MB; upload it to Cloud Storage first.")
    agents = load_agents(BRIEF)
    if args.agents:
        wanted = set(args.agents.split(","))
        agents = [a for a in agents if a["id"] in wanted]
    video_part = {"inlineData": {"mimeType": "video/mp4", "data": base64.b64encode(video.read_bytes()).decode()}}

    out = OUTPUT / re.sub(r"[^A-Za-z0-9_-]+", "-", video.stem).strip("-")[:60]
    out.mkdir(parents=True, exist_ok=True)
    print(f"{len(agents)} agents on {video.name} via {vertex.mode}, model {model}", flush=True)

    def job(agent):
        try:
            result, seconds = run_agent(vertex, agent, video_part)
            (out / f"{agent['id']}.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
            print(f"  done   {agent['id']} ({seconds:.0f}s)", flush=True)
            return agent["id"], result, None
        except (RuntimeError, ValueError, KeyError, IndexError) as error:
            print(f"  failed {agent['id']}: {error}", flush=True)
            return agent["id"], None, str(error)

    with ThreadPoolExecutor(max_workers=len(agents)) as pool:
        results = list(pool.map(job, agents))

    master = {"source_video": video.name, "model": model,
              "agents": {agent_id: result for agent_id, result, _ in results if result is not None},
              "failed": {agent_id: error for agent_id, _, error in results if error}}
    (out / "master_state.json").write_text(json.dumps(master, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(master['agents'])}/{len(agents)} agents succeeded -> {out.relative_to(ROOT)}/master_state.json")
    if master["failed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
