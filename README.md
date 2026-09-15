# PlayScript

A native, offline SwiftUI story experience for **iOS 18+**. Live *Romeo & Juliet* through Juliet’s eyes, with an explicitly imagined final scene through Romeo’s.

## Run

1. Open `PlayScript.xcodeproj` in Xcode 16 or later.
2. Select the **PlayScript** scheme and an iPhone simulator, then Run.
3. For a physical iPhone, choose your development team under **Signing & Capabilities**. The default bundle identifier is `com.sh1vendra.PlayScript`.

There are no third-party runtime dependencies, account requirements, API keys, or network calls. The local `StoryCore` Swift package is included in the repository. The app is designed for portrait iPhones.

## The experience

- A cream, rose, and burgundy library with a custom glass treatment and literary typography.
- One story, presented in 19 short reading beats across the requested fixed sequence.
- Exactly two thoughts at each of three decisions. A selected thought lingers as the other fades, then reveals its own flavor text. Every choice reaches the same next beat.
- A quiet fade into the “what if” ending, explicitly distinguished from Shakespeare’s tragedy.
- A closing reflection, replay, and automatic restoration of both your place and selected flavor text.
- Five original ambient loops with mood crossfades, plus gentle page and choice sounds. Sound respects the silent switch, pauses when the app becomes inactive, and can be turned off in the library or pause sheet.
- Dynamic Type, scrollable text, VoiceOver reading focus and pause actions, Reduce Motion, and Reduce Transparency.

Tap **Become Juliet** to begin. Use **Tap to continue** to turn a page. Touch and hold anywhere in the story to pause, adjust sound, or return to the library. VoiceOver also exposes **Pause story** as a custom action and supports the escape gesture.

## Illustration status

**Scene illustrations are deferred at the user’s request.** This build uses a temporary typographic backdrop with restrained framing and mood colors. These are artwork placeholders, not the finished illustrated experience from the original brief.

The reader already accepts a local asset name through each beat’s optional `artwork` field. Add commissioned/approved images to `PlayScript/Resources/Assets.xcassets`, then set those names in the story JSON. The artwork fills the screen behind the reading scrim. See [ARTWORK.md](ARTWORK.md) for framing and scene notes. No images are generated or fetched at runtime.

## Structure

| Location | Purpose |
| --- | --- |
| `StoryCore/Sources/StoryCore/Resources/romeo-and-juliet.json` | Prose, two-choice decisions, flavor text, point of view, mood, and artwork references |
| `StoryCore/Sources/StoryCore/Story.swift` | Content validation, fixed-order progression, stable-ID saved places |
| `PlayScript/App` | App lifecycle, persistence, confirmation timing, reading state |
| `PlayScript/Features` | Library, reader, pause, imagined ending, reflection |
| `PlayScript/Design` | Colors, type, custom glass, artwork integration |
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
swift Scripts/create_icon.swift # macOS AppKit; typeset app mark
python3 Scripts/create_project.py
```

The project generator uses only Python’s standard library. Rerun it when adding Swift source files or individual audio resources. Xcode asset-catalog additions and edits to existing source/data files do not require regeneration.

## Content notes

The prose is an original adaptation of Shakespeare’s public-domain play. The main telling preserves the secret marriage, Tybalt’s death and Romeo’s banishment, the arranged marriage to Paris, the sleeping potion, the undelivered letter, and the lovers’ tragic ending. Death is handled without graphic imagery. The final road-and-tomb sequence is expressly counterfactual, and is not presented as Shakespeare’s ending.
