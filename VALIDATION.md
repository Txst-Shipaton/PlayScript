# Build verification

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
