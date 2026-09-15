Scene & Voice Direction Brief
Product: ActiveStory, a literary interactive-fiction game (React 19 + Vite, SVG-based scenes). This brief covers visual direction, animation architecture, voice/audio, and the decision-moment interaction for one chapter ("The quiet mistake," workshop scene) as a demo vertical slice.

1. Visual philosophy
Cinematic, illustrated-theatre, literary noir — but restrained, not maximalist. Not every scene needs a dramatic set-piece; most should feel quietly alive through small consistent detail, with intensity reserved for the moments that earn it (a consequence landing, a decision, a rewind). The bar is "this is not a static illustration you read text over" — never "this is a spectacle."

2. Rendering split: pre-rendered vs. live-animated
To keep this fast and deterministic (no live image generation, no per-frame render cost):

Pre-rendered once, offline, per scene: backgrounds, color grading, lighting mood, atmospheric texture (grain, vignette, painterly gradients). These are static assets — a WebP or a base SVG layer — authored per scene/mood combination ahead of time, not computed live.
Live SVG/CSS/WAAPI, only for what benefits from motion: characters, light sources (lamp, window glow), small foreground props (dust, paper, rain), and any element that reacts to story state. If it can't meaningfully move or react, it belongs in the pre-rendered layer, not the animated one.
This split is deliberate: it lets us look expensive without needing a rendering pipeline that has to work live in front of an audience.

3. Per-scene "quirk"
Each scene gets one small, specific recurring motion detail that's unique to it and repeats subtly throughout — not generic ambient loop reused everywhere. Examples: the workshop's press casts a faint moving shadow every ~40s; the bridge scene has a single gull crossing the sky every couple minutes; the room's curtain shifts once when a door "closes" off-screen. The point: a viewer who sits still for 30 seconds should notice something happen that they didn't consciously trigger, so no scene ever reads as a paused slideshow.

4. Mobile layout
Full-bleed: the scene fills the entire screen, no chrome around it. Dialogue/narration sits as a bottom overlay on a dark gradient scrim over the art (not a separate panel). When a choice moment arrives, exactly two options are presented as the fixed bottom UI — large touch targets, no button-grid, text reads as a considered thought, not an A/B quiz answer.

5. Voice (ElevenLabs)
One consistent voice per character, deterministically mapped (character id → voice id), never re-rolled — the same character always sounds the same across the whole playthrough.
Pacing target: 165–175 WPM with natural intonation — question rises, declarative statements land firm, pauses on commas/em-dashes are real pauses, not uniform typewriter timing.
Synced subtitles: word-level highlight-as-spoken (color shift or weight change on the current word), driven off ElevenLabs' timestamp/alignment data, not a naive character-count timer — so highlight timing survives variable word length and pause placement.
6. The decision moment
This is the one moment that should feel physically different from reading. When a choice point arrives:

The scene visually yields center stage — background motion slows, camera settles, everything else quiets.
The two options don't appear as static buttons; they animate into place as if they're thoughts entering the character's mind — a soft rise/settle, not a menu popping open.
On hover/focus, the scene should react subtly (a gaze shift, a light change) before commitment, so the choice feels weighed, not clicked.
On commit: the unchosen option visibly falls away, a brief freeze (~150–250ms), then the story continues. The player should feel the decision land, not just navigate past it.