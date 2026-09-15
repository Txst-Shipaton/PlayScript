# Scene artwork handoff

The `screenupdate` branch includes authored native vector scenery in
`PlayScript/Design/LivingScene.swift`. Static architecture and silhouettes are
drawn once per scene update. Movement comes from three sources: the curtain and
light layer, a Lottie animation per setting, and a continuous atmosphere `Canvas`.
The split is deliberate — Lottie carries choreographed motion (petals, candle
flame, tomb light and mist, birds), the `Canvas` carries dense particle fields
(fireflies, embers, dust, road grit), and nothing is drawn twice. Motion dims and
slows for decisions and stops entirely for pause, backgrounding, and Reduce Motion.

The Lottie files are authored as JSON by `Scripts/create_lottie.py`; none was
downloaded or made in a design tool. No raster scene art or SVG is used: SwiftUI
has no native SVG renderer, and the vector scenery is drawn directly instead.

The following notes remain a direction for future commissioned raster artwork.

## Delivery

Use illustrated, storybook-style images rather than photography. Warm cream, muted rose, and soft red should anchor the palette. Tense scenes may cool toward desaturated plum, without turning neon or corporate. Keep characters and important details in the upper half: narrative text overlays the lower portion, and some cropping occurs across iPhone sizes.

- Suggested master: 1290 × 2796 px portrait, opaque sRGB, PNG or high-quality JPEG.
- Compose for center cropping, with generous space at the sides and top.
- No baked-in text, buttons, dialogue, or HUD.
- Avoid graphic depictions of death. The tomb should communicate stillness and loss through light and composition.
- The same illustration can support adjacent beats; the reader’s mood tint supplies continuity until separately lit variants are approved.

## Proposed assets

| Suggested asset name | Beats | Direction |
| --- | --- | --- |
| `verona-window` | `window`, `window-choice` | A moonlit orchard viewed from Juliet’s window; a tender, secret beginning |
| `orchard-vow` | `names`, `vow`, `vow-choice` | The balcony and orchard, warmer light as the vow becomes real |
| `verona-morning` | `morning` | Dawn at the same window, restrained and hopeful |
| `friar-letter` | `friar`, `plan` | A small vial and a handwritten letter in the Friar’s quiet cell |
| `juliet-chamber` | `potion-choice`, `sleep` | Candlelit chamber, softened shadows, the little vial |
| `tomb-silence` | `wake`, `letter-lost`, `last-kiss`, `what-if` | Stone and dim light, grief without graphic detail |
| `letter-road` | `road`, `ride` | A messenger’s letter, a road toward Verona, returning morning light |
| `tomb-dawn` | `in-time`, `enough-time`, `reflection` | A hand held in the first light; Romeo arrives in time |

The title card now uses the native orchard composition; connect approved cover
artwork at `LibraryView.storyCard` by passing the asset to `SceneBackdrop`. The
reader uses `LivingScene` directly. To introduce raster backgrounds there, replace
its static `scenery` layer and keep the interactive light/foreground layers; the
JSON `artwork` names alone will not change the current reader.
