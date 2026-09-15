# PlayScript

A native, offline SwiftUI story experience for **iOS 18+**. Live *Romeo & Juliet* through Juliet’s eyes, with an explicitly imagined final scene through Romeo’s.

## Run

1. Open `PlayScript.xcodeproj` in Xcode 16 or later.
2. Select the **PlayScript** scheme and an iPhone simulator, then Run.
3. For a physical iPhone, choose your development team under **Signing & Capabilities**. The default bundle identifier is `com.sh1vendra.PlayScript`.

The app has one third-party runtime dependency, [lottie-ios](https://github.com/airbnb/lottie-ios), resolved by Xcode on first build; that build step needs network access, the app itself does not. There are no account requirements, API keys, or runtime network calls. The local `StoryCore` Swift package is included in the repository. The app is designed for portrait iPhones.

## The experience

- A cream, rose, and burgundy library with a custom glass treatment and literary typography.
- One story, presented in 19 short reading beats across the requested fixed sequence.
- Both lovers speak. Each beat is written as attributed lines, and the reader shows
  **two lines at a time** rather than a block of prose, so Romeo can answer Juliet
  within a page. Each line is narrated in its own character's voice, and the lines
  of a page play in order.
- Exactly two thoughts at each of three decisions. Thoughts rise into view; the selected thought lingers as the other falls away, then reveals its own flavor text. Every choice reaches the same next beat.
- A quiet fade into the “what if” ending, explicitly distinguished from Shakespeare’s tragedy.
- A closing reflection, replay, and automatic restoration of both your place and selected flavor text.
- Five original ambient loops with mood crossfades, plus gentle page and choice sounds. Sound respects the silent switch, pauses when the app becomes inactive, and can be turned off in the library or pause sheet.
- Dynamic Type, scrollable text, VoiceOver reading focus and pause actions, Reduce Motion, and Reduce Transparency.

Tap **Become Juliet** to begin. Use **Tap to continue** to turn a page. Use the pause icon or touch and hold in the story to pause, adjust sound, or return to the library. VoiceOver also exposes **Pause story** as a custom action and supports the escape gesture.

## Screen update

The `screenupdate` branch adapts `screens.md` to this native iOS app. Scenes are
built in three layers:

1. **Static scenery** — authored SwiftUI vector drawing per setting (orchard,
   chamber, tomb, dawn road), drawn once per scene change.
2. **Lottie** — the choreographed motion: falling petals, the candle flame, the
   tomb's breathing light shaft and crawling mist, and birds crossing the dawn with
   beating wings. Also two accents: the letter on the “what if” page and the thought
   blooming behind a decision.
3. **Native `Canvas` atmosphere** — the dense particle fields that are cheaper drawn
   directly: fireflies, embers, tomb dust, road grit.

Each setting also keeps one slower discrete quirk. A decision slows the Lottie
layer to 40% speed and dims both motion layers, so the scene yields to the choice.
Reduce Motion, pause, and backgrounding stop everything.

The Lottie animations are authored as JSON by `Scripts/create_lottie.py` — no design
tool and no downloaded asset is involved — and their structure is covered by tests:

```sh
python3 Scripts/create_lottie.py
python3 -m unittest discover -s Scripts -p 'test_*.py'
```

Because Lottie is decorative, a missing animation degrades to nothing: the scenery
and atmosphere layers keep every scene in motion on their own. Decision scenes settle,
thoughts enter in sequence, focus/hover changes the light, and the unchosen
thought falls away before the selected response appears. Reduce Motion disables
the ambient loops and movement. Normal text sizes use bottom-anchored controls;
accessibility sizes keep the narrative and controls together in a scroll view.

### Optional ElevenLabs narration

Put `ELEVENLABS_API_KEY=...` in the root `.env` (already ignored). The existing
`elevenlabs=...` spelling is also supported. Use the secret key, not its key ID. See
`.env.example` for the two fixed character voice mappings. The key is used by
the offline Python script only; the app reads bundled MP3 and JSON files.

```sh
python3 Scripts/create_narration.py                  # free inventory
python3 Scripts/create_narration.py --prune          # drop clips the script dropped
python3 Scripts/create_narration.py --generate       # uses ElevenLabs credits
python3 Scripts/create_score.py --generate           # music cues and effects
python3 Scripts/create_project.py                    # include generated clips
python3 -m unittest discover -s Scripts -p 'test_*.py'
```

Narration is generated **per line**, not per passage: 110 clips, 74 Juliet and 36
Romeo, each named `voice-<beat>[--<choice>]-l<line>`. The speaker on the line picks
the voice, so a page can change speaker mid-way. Those clips, five mood score cues,
and seven effects are all generated and checked in, so playback is immediate and
entirely offline.

Delivery is tuned for a human reading rather than an even one: stability is kept low
(the provider treats high stability as flat delivery, which is what sounds robotic),
style carries the mood, and the pitch-preserving playback-rate correction is now
clamped to ±6% — a reading that is naturally off-pace is left alone instead of being
stretched. Set `ELEVENLABS_JULIET_VOICE_ID` or `ELEVENLABS_ROMEO_VOICE_ID` in `.env`
to recast either part, then rerun with `--prune --generate`. `create_score.py` writes
`PlayScript/Resources/Score`: `score-<mood>.mp3` per mood and `fx-<name>.mp3` for the
four location loops (orchard, candle, tomb, road) and three gestures (letter, choice,
turn). `Soundscape` prefers these over the original synthesized WAVs and falls back to
them when a clip is absent. A quiet location loop plays under the score, so each
setting keeps its own room tone; the letter gesture replaces the page turn on the
beats where the Friar's letter turns the plot.

Generation reuses cached clips whose text, voice, and settings match. Use
`--limit 1` for one new clip. Each cue comes from the [ElevenLabs timestamps
endpoint](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps).
Whitespace and paragraph breaks are preserved exactly. The generator measures
the spoken span and stores a bounded playback rate targeting 170 WPM; inspect
`effectiveWPM` in each metadata file and listen before release. Highlighting uses
the actual audio position, including at adjusted playback rates. Missing or stale
voice assets leave the original text readable without simulated highlighting.

The Read aloud toggle appears when the current passage has bundled narration.
Voice pauses with the story and app lifecycle. Audio respects the silent switch.
This branch still needs Xcode compilation and simulator/device visual and audio QA;
see the current-run section in `VALIDATION.md`.

## Illustration integration

The screen update replaces the temporary typographic scenery with native vector
illustrations. These are authored geometric theatre scenes, not raster paintings.

Optional local artwork names remain in the story data and library cover component.
The reader uses `LivingScene` for its responsive native composition. No images are
generated or fetched at runtime.

## Structure

| Location | Purpose |
| --- | --- |
| `StoryCore/Sources/StoryCore/Resources/romeo-and-juliet.json` | Prose, two-choice decisions, flavor text, point of view, mood, and artwork references |
| `StoryCore/Sources/StoryCore/Story.swift` | Content validation, fixed-order progression, stable-ID saved places |
| `PlayScript/App` | App lifecycle, persistence, confirmation timing, reading state |
| `PlayScript/Features` | Library, reader, pause, imagined ending, reflection |
| `PlayScript/Design` | Colors, type, custom glass, scenery, Lottie hosting |
| `PlayScript/Resources/Lottie` | Authored scene and accent animations |
| `PlayScript/Resources/Score` | Generated ElevenLabs music cues and effects |
| `PlayScript/Audio` | Bundled playback, mood crossfades, interruption handling |
| `PlayScript/Resources/Audio` | Original PCM audio, generated once at development time |

Choices deliberately have **no destination field**. To change emotional tone, edit the choice’s `flavor`. Plot progression always moves to the next beat in the array. Stable beat IDs allow wording changes without invalidating a saved place; missing IDs fall back to the beginning safely.

## Validate

Run the engine tests on macOS:

```sh
swift test --package-path StoryCore
```

Build for a simulator:

```sh
xcodebuild -project PlayScript.xcodeproj -scheme PlayScript \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
```

Run the UI tests with **Product → Test**, or replace `SIMULATOR_ID` with an available identifier from `xcrun simctl list devices`:

```sh
xcodebuild -project PlayScript.xcodeproj -scheme PlayScript \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath build test CODE_SIGNING_ALLOWED=NO
```

The engine tests cover all eight decision combinations, invalid content, stale saves, flavor restoration, and the point-of-view boundary. UI tests cover a complete read and replay, save/resume, pause, accessibility text scrolling, sound preferences, and background/foreground transitions. Screenshot attachments are retained in the test result bundle.

See [VALIDATION.md](VALIDATION.md) for the tested devices, results, and runtime limitations.

## Recreate development assets

The generated audio and icon are already checked in; these steps are optional:

```sh
python3 Scripts/create_audio.py  # Python 3 + numpy; seven original WAV files
python3 Scripts/create_lottie.py # authored Lottie JSON; standard library only
swift Scripts/create_icon.swift # macOS AppKit; typeset app mark
python3 Scripts/create_project.py
```

The project generator uses only Python’s standard library. Rerun it when adding Swift source files or individual audio resources. Xcode asset-catalog additions and edits to existing source/data files do not require regeneration.

## Content notes

The prose is an original adaptation of Shakespeare’s public-domain play. The main telling preserves the secret marriage, Tybalt’s death and Romeo’s banishment, the arranged marriage to Paris, the sleeping potion, the undelivered letter, and the lovers’ tragic ending. Death is handled without graphic imagery. The final road-and-tomb sequence is expressly counterfactual, and is not presented as Shakespeare’s ending.
