# Build verification

## Current screenupdate run · September 14, 2026

The results below this section describe the prior branch baseline, **not** a
verification of the screen update on this machine.

- Swift syntax parsing of the changed app sources passed with
  `swiftc -frontend -parse -parse-stdlib …`; this is not type checking or an iOS build.
- Three Python alignment tests passed, covering exact paragraph/punctuation reconstruction,
  provider text mismatch, missing alignment, and invalid cue times.
- The Xcode project generator includes the new Swift files, the generated
  narration MP3/JSON files, and the generated score/effect MP3 files. It does not
  include `.env`.
- `.env` and `.env.*` are ignored, except the empty `.env.example` template.
- The replaced ElevenLabs key is accepted. All 25 narration clips generated, each
  with provider character alignment; reported effective rates are 163–170 WPM.
  Five mood score cues and seven effects generated (5.6 MB narration, 3.2 MB score).
- **Not listened to.** No audio was played back on this machine. Voice casting,
  per-mood delivery, music, loop seams, and the ambience/score/voice balance are
  unverified; the mix levels in `Soundscape` are chosen, not tuned by ear.
- The new `LivingScene` atmosphere layer and the `Soundscape` ambience layer have
  **never been compiled or rendered**. Both are new code paths on an unbuildable
  machine; treat first Xcode run as the real test.
- Six Lottie animations are authored by `Scripts/create_lottie.py` and pass nine
  structural tests: schema completeness, unique layer indexes, a trailing transform
  in every shape group, monotonic in-range keyframe times, matching first/last
  keyframes for seamless looping, interpolation handles sized to their value,
  constant vertex counts across path morphs, and colour/opacity ranges.
- **No Lottie animation has been rendered.** The tests prove the files are
  structurally valid, not that they look good, and a malformed Lottie fails
  silently by simply not playing. Composition, timing, scale, and colour are
  unreviewed.
- The `lottie-ios` package reference was written into the project by the generator
  and has **never been resolved by Xcode**. First build requires network access and
  may need a version adjustment; `import Lottie` has not been compiled.
- `swift test --package-path StoryCore` could not load the existing manifest:
  this installed command-line toolchain cannot resolve `.iOS(.v18)`.
- Xcode and `simctl` are unavailable. iOS compilation, complete-story UI tests,
  small-phone/large-text layouts, animation timing, VoiceOver, and audio playback
  have **not been verified** for this update.

Next on an Xcode machine: build first, then run the existing engine and UI tests and
inspect all four scene settings. Check choice focus/hover, pause during a pending
choice, foreground/background return, voice on/off, Reduce Motion, and the largest
accessibility text sizes. Listen to both voices and confirm word highlighting follows
playback, including pauses.

Specific to this run, and all unverified:

- Resolve `lottie-ios` and confirm the app compiles before anything else.
- Watch the combined cost of the two motion layers. The `Canvas` redraws at 30 fps
  and a Lottie animation plays over it; confirm on the oldest supported device that
  they do not warm the phone or drain battery, and that both truly stop for Reduce
  Motion, pause, and backgrounding.
- Look at each of the four scene animations. Check that the Lottie elements sit
  where the scenery expects them — particularly the chamber flame, which is
  positioned to meet the drawn candle at (0.72, 0.395) and will look wrong if the
  aspect-fill crop shifts it.
- Confirm the accents read well: the letter on the “what if” page and the thought
  rings behind a decision, which must not compete with the choice text.
- Balance the three simultaneous audio sources (score, location ambience, narration).
  Ambience is set to 55% of the score volume, which is a guess.
- Confirm the score and effect loops are seamless. ElevenLabs was asked for looping
  audio, but the seams have not been heard.
- Confirm the candle, fireflies, dust, and birds read as intended rather than as
  noise over the text, at both normal and accessibility text sizes.

## Environment

- Xcode 27.0, Swift 6.4 toolchain.
- App deployment target: **iOS 18.0**.
- Installed simulator runtime: iOS 27.0.
- Layouts exercised on iPhone 18 Pro (402 × 874 points) and iPhone SE third-generation (375 × 667 points) simulators.

An iOS 18 runtime and physical iPhone were not available for testing. The device Release build’s `MinimumOSVersion` is verified as `18.0`; that is a deployment check, not a claim of execution on iOS 18 hardware.

## Completed checks

| Check | Result |
| --- | --- |
| Story engine | Five tests passed; includes all eight combinations of the three choices |
| Full story and replay | Passed on standard and SE-sized simulators |
| Save, terminate, relaunch, restore flavor | Passed on both sizes |
| Pause and return to library | Passed on both sizes |
| Sound preference and background/foreground return | Passed; final standard-iPhone check waits for the foreground animation before testing pause |
| Largest accessibility text size | Narrative and choices remained scrollable and reachable on both sizes |
| Release for a physical iPhone | Unsigned ARM64 build succeeded; minimum iOS version 18.0 |
| Project generator | Reproduces the checked-in project without differences |
| Bundled assets | Seven original WAV files; valid icon, asset catalog, story JSON, and privacy manifest |
| Visual review | Library, opening, choices, imagined ending, reflection, pause sheet, and app icon inspected |

Audio playback and session activation use a dedicated serial queue. The app makes no runtime network requests. The WAVs are rendered at development time from original tones and noise, without downloaded samples.

## Deliberately deferred

Scene illustrations are on hold at the user’s request. The typographic backdrops are temporary. See [ARTWORK.md](ARTWORK.md) for asset integration notes.

Device signing requires selecting a development team in Xcode. Physical-device checks of the silent switch, headphones, and phone-call interruptions remain outside the simulator verification above.
