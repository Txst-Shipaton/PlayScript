# Scene artwork handoff

Illustrations are on hold. No scene art has been generated or downloaded.

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

Add each approved asset to the catalog and replace the corresponding JSON `artwork: null` with its asset name. The title card currently uses the same temporary typographic treatment; connect approved cover artwork at `LibraryView.storyCard` by passing the asset to `SceneBackdrop`.
