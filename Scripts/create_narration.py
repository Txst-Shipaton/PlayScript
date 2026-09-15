#!/usr/bin/env python3
"""Generate bundled narration once. Secrets are read locally, never included in outputs.

Run without flags for a free inventory; --generate calls ElevenLabs for missing clips.
Existing matching clips are reused. --limit bounds new API calls.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "PlayScript/Resources/Narration"
DELIVERY = {
    "longing": {"emotion": "intimate, wondering, quietly breathless", "stability": 0.42, "style": 0.38},
    "tender": {"emotion": "warm, certain, gently joyful", "stability": 0.52, "style": 0.32},
    "uneasy": {"emotion": "frightened resolve, contained urgency", "stability": 0.35, "style": 0.48},
    "grief": {"emotion": "devastated, hushed, space between thoughts", "stability": 0.62, "style": 0.42},
    "dawn": {"emotion": "disbelief giving way to relief and hope", "stability": 0.45, "style": 0.38},
}


def environment():
    values = {}
    path = ROOT / ".env"
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.removeprefix("export ").split("=", 1)
            values[name.strip()] = value.strip().strip("\"'")
    return values | dict(os.environ)


def word_cues(text, alignment):
    """Preserve exact whitespace while folding character times into word spans."""
    if not alignment or "".join(alignment["characters"]) != text:
        raise ValueError("Alignment does not exactly match the source text; no approximate cues saved.")
    starts = alignment["character_start_times_seconds"]
    ends = alignment["character_end_times_seconds"]
    if len(starts) != len(text) or len(ends) != len(text):
        raise ValueError("Incomplete alignment")
    cues = []
    for match in re.finditer(r"\s*\S+\s*", text):
        nonspace = [i for i in range(match.start(), match.end()) if not text[i].isspace()]
        cues.append({"text": match.group(), "start": starts[nonspace[0]], "end": ends[nonspace[-1]]})
    if "".join(c["text"] for c in cues) != text:
        raise ValueError("Cue text reconstruction failed")
    if any(c["start"] < 0 or c["end"] < c["start"] for c in cues):
        raise ValueError("Invalid cue times")
    if any(a["start"] > b["start"] for a, b in zip(cues, cues[1:])):
        raise ValueError("Nonmonotonic cue times")
    return cues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--limit", type=int, default=25)
    args = parser.parse_args()
    env = environment()
    key = next((env[k] for k in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY", "ELEVEN_API_KEY", "elevenlabs") if env.get(k)), None)
    voices = {
        "Juliet": env.get("ELEVENLABS_JULIET_VOICE_ID", "EXAVITQu4vr4xnSDxMaL"),
        "Romeo": env.get("ELEVENLABS_ROMEO_VOICE_ID", "onwK4e9ZLuTAKqWW03F9"),
    }
    story = json.loads((ROOT / "StoryCore/Sources/StoryCore/Resources/romeo-and-juliet.json").read_text())
    clips = []
    for beat in story["beats"]:
        clips.append((beat["id"], beat["pointOfView"], beat["text"], beat["mood"]))
        clips.extend((beat["id"] + "--" + c["id"], beat["pointOfView"], c["flavor"], beat["mood"]) for c in beat["choices"])
    print(f"{len(clips)} clips; {sum(len(c[2]) for c in clips)} characters; API key {'present' if key else 'missing'}.")
    if not args.generate:
        return
    if not key:
        raise SystemExit("Set ELEVENLABS_API_KEY in the root .env file, then rerun.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    generated = 0
    for clip_id, character, text, mood in clips:
        delivery = DELIVERY[mood]
        payload = {"text": text, "model_id": "eleven_multilingual_v2", "seed": 42,
                   "voice_settings": {"stability": delivery["stability"], "similarity_boost": 0.8,
                                      "style": delivery["style"], "speed": 1.0}}
        fingerprint = hashlib.sha256(json.dumps([voices[character], payload], sort_keys=True).encode()).hexdigest()
        metadata = OUTPUT / f"voice-{clip_id}.json"
        audio = OUTPUT / f"voice-{clip_id}.mp3"
        if metadata.exists() and audio.exists() and json.loads(metadata.read_text()).get("fingerprint") == fingerprint:
            print(f"Cached: {clip_id}")
            continue
        if generated >= args.limit:
            break
        request = urllib.request.Request(
            f"https://api.elevenlabs.io/v1/text-to-speech/{voices[character]}/with-timestamps?output_format=mp3_44100_128",
            data=json.dumps(payload).encode(), headers={"xi-api-key": key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            # Never dump request headers or the provider response (which may contain account data).
            try:
                detail = json.load(error).get("detail", {})
                status = detail.get("status", "unknown") if isinstance(detail, dict) else "validation_error"
                status = status if re.fullmatch(r"[a-z_]+", str(status)) else "unknown"
            except (ValueError, AttributeError):
                status = "unknown"
            raise SystemExit(f"ElevenLabs returned HTTP {error.code} ({status}); check key permissions, voice access, and credits.") from None
        cues = word_cues(text, result.get("alignment"))
        duration = cues[-1]["end"]
        # AVAudioPlayer's time is in source seconds even when its playback rate changes.
        # Pitch-preserving rate calibration makes the spoken span target 170 WPM.
        source_wpm = len(text.split()) / duration * 60
        rate = max(0.7, min(1.3, 170 / source_wpm))
        effective_wpm = source_wpm * rate
        audio.write_bytes(base64.b64decode(result["audio_base64"], validate=True))
        metadata.write_text(json.dumps({"text": text, "cues": cues, "playbackRate": rate,
                                       "voiceID": voices[character], "character": character,
                                       "mood": mood, "deliveryDirection": delivery["emotion"],
                                       "fingerprint": fingerprint, "effectiveWPM": effective_wpm}, ensure_ascii=False, indent=2) + "\n")
        generated += 1
        print(f"Generated: {clip_id} ({effective_wpm:.0f} WPM)", flush=True)
    print("Run python3 Scripts/create_project.py to include generated resources in Xcode.")


if __name__ == "__main__":
    main()
