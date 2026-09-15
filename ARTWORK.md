# Scene animation handoff

Ten lightweight Lottie animations are bundled under `PlayScript/Resources/Animations`. They contain vector shapes only, with no text, raster images, or downloaded media.

## Delivery

Use illustrated, storybook-style images rather than photography. Warm cream, muted rose, and soft red should anchor the palette. Tense scenes may cool toward desaturated plum, without turning neon or corporate. Keep characters and important details in the upper half: narrative text overlays the lower portion, and some cropping occurs across iPhone sizes.

- Suggested master: 1290 × 2796 px portrait, opaque sRGB, PNG or high-quality JPEG.
- Compose for center cropping, with generous space at the sides and top.
- No baked-in text, buttons, dialogue, or HUD.
- Avoid graphic depictions of death. The tomb should communicate stillness and loss through light and composition.
- The same illustration can support adjacent beats; the reader’s mood tint supplies continuity until separately lit variants are approved.

## Animation mapping

| Filename | Beats | Direction |
| --- | --- | --- |
| `opening.json` | `window` | Window light, candle flicker, gently swaying curtains |
| `balcony_choice.json` | `window-choice` | Moonlight and a moth circling near the balcony |
| `confession.json` | `names`, `vow` | Warm bloom with upward-drifting light motes |
| `vow_choice.json` | `vow-choice`, `morning` | Deep burgundy night and subtle starlight |
| `the_letter.json` | `friar`, `plan` | Amber candlelight and incense-like motes |
| `vial_choice.json` | `potion-choice`, `sleep` | A more unstable amber flicker |
| `the_tomb.json` | `wake`, `letter-lost`, `last-kiss` | Pale stone arch and very slow dust |
| `whatif_prompt.json` | `what-if` | Nearly still suspended light and a single mote |
| `whatif.json` | `road`, `ride`, `in-time`, `enough-time` | Rising dawn glow and hopeful particles |
| `closing.json` | `reflection` | Soft breathing glow and resting light |

Run `python3 Scripts/create_animations.py` to regenerate all ten files deterministically. Their filenames are part of the app contract and must not change. Future commissioned illustrations can still be supplied through the story JSON’s `artwork` field.
