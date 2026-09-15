#!/usr/bin/env python3
"""Offline ElevenLabs score/effects. Cached by prompt; bounded to 12 assets per run."""
import argparse
import hashlib
import json
import re
import urllib.error
import urllib.request
from create_narration import ROOT, environment

OUTPUT = ROOT / "PlayScript/Resources/Score"
MUSIC = {
    "longing": "Moonlit Renaissance orchard. Intimate literary film score, plucked lute harmonics, low soft strings, suspended yearning, 64 BPM, delicate space for spoken narration, no drums, no vocals, a quiet circular ending.",
    "tender": "A secret vow at a moonlit balcony. Warm chamber strings, soft harp and felt piano, tender rising motif, intimate hopeful romance, 70 BPM, restrained dynamics underneath speech, no vocals, no percussion, circular ending.",
    "uneasy": "A sleeping potion in a candlelit chamber. Dark chamber score, trembling viola, muted low cello pulses, glass harmonics, contained dread and brave resolve, 60 BPM, no loud hits, no vocals, space for narration, circular ending.",
    "grief": "A silent stone tomb. Elegiac solo cello, sparse low felt piano, long reverberant rests, profound human loss without horror, very quiet 50 BPM, no vocals, no percussion, circular ending.",
    "dawn": "A letter delivered in time, two lovers reunited at dawn. Warm hopeful chamber score, flowing harp, rising cello and soft string harmonics, 76 BPM, gentle relief not a triumphant fanfare, no vocals, space for narration, circular ending.",
}
EFFECTS = {
    "orchard": (12, True, "Quiet night orchard atmosphere, soft leaves rustling in wind and distant crickets, a very distant owl, no music or voices, smooth seamless loop."),
    "candle": (12, True, "Intimate candlelit old stone room, gentle tiny wick crackle, distant wind through an old window, no music or voices, seamless quiet loop."),
    "tomb": (12, True, "Quiet cavernous stone chamber, faint wind and sparse water drops echoing far away, subtle airy low room tone, no voices, no horror stingers, seamless loop."),
    "road": (12, True, "Soft horse hoofbeats along a dirt road, leather and leaves in gentle dawn wind, distant morning birds, no voices or music, seamless loop."),
    "letter": (3, False, "Close delicate parchment unfolding and a wax seal softly cracking, one intimate dry foley gesture, no music or voices."),
    "choice": (2, False, "One soft cinematic heartbeat followed by a breath of air and a warm glass resonance, intimate decision moment, restrained, no voices or music."),
    "turn": (1, False, "One soft old book page turning, textured paper and a delicate cloth rustle, close and quiet, no music or voices."),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--kind", choices=["all", "music", "effects"], default="all")
    args = parser.parse_args()
    env = environment()
    key = next((env[k] for k in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY", "ELEVEN_API_KEY", "elevenlabs") if env.get(k)), None)
    jobs = []
    if args.kind != "effects":
        jobs += [("score-" + name, "music", {"prompt": prompt, "music_length_ms": 30000,
                  "force_instrumental": True, "model_id": "music_v1"}) for name, prompt in MUSIC.items()]
    if args.kind != "music":
        jobs += [("fx-" + name, "sound-generation", {"text": prompt, "duration_seconds": duration,
                  "loop": loop, "model_id": "eleven_text_to_sound_v2", "prompt_influence": 0.45})
                 for name, (duration, loop, prompt) in EFFECTS.items()]
    print(f"{len(jobs)} score/effect assets planned; 30 seconds per music cue.", flush=True)
    if not args.generate:
        return
    if not key:
        raise SystemExit("Missing ElevenLabs secret key")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    failures = []
    for name, endpoint, payload in jobs:
        fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
        audio, metadata = OUTPUT / (name + ".mp3"), OUTPUT / (name + ".json")
        if audio.exists() and metadata.exists() and json.loads(metadata.read_text()).get("fingerprint") == fingerprint:
            print(f"Cached: {name}", flush=True)
            continue
        request = urllib.request.Request("https://api.elevenlabs.io/v1/" + endpoint + "?output_format=mp3_44100_128",
                   data=json.dumps(payload).encode(), headers={"xi-api-key": key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=240) as response:
                content = response.read()
            if len(content) < 1000:
                raise ValueError("Empty audio response")
            audio.write_bytes(content)
            metadata.write_text(json.dumps({"provider": "ElevenLabs", "fingerprint": fingerprint,
                                           "request": payload}, indent=2) + "\n")
            print(f"Generated: {name}", flush=True)
        except urllib.error.HTTPError as error:
            try:
                detail = json.load(error).get("detail", {})
                code = detail.get("status", "unknown") if isinstance(detail, dict) else "validation_error"
                code = code if re.fullmatch(r"[a-z_]+", str(code)) else "unknown"
            except (ValueError, AttributeError):
                code = "unknown"
            print(f"Unavailable: {name}: HTTP {error.code} ({code})", flush=True)
            failures.append(name)
            # Auth/quota errors cannot be fixed by spending more requests.
            if error.code in (401, 402, 429) or code in ("quota_exceeded", "api_key_id_used_as_api_key"):
                break
            if endpoint == "music":
                # A denied music capability should not prevent effect generation.
                jobs = jobs  # Iteration remains bounded; run --kind effects separately if needed.
    if failures:
        raise SystemExit("Some assets unavailable; existing original soundscapes remain the fallback.")


if __name__ == "__main__":
    main()
