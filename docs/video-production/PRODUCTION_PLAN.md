# PitchMark Video Production Plan

## Creative direction

PitchMark should feel like an Apple product demonstration set inside a premium night-game atmosphere: quiet, precise, and confident. The interface is the hero. The sports environment adds emotion but never competes with the lesson.

The production should create two deliverables from one shared capture library:

1. **Marketing film** — 45 seconds, 1920 × 1080, cinematic field environment, floating iPhone, website/social use.
2. **App Store preview** — 30 seconds, 886 × 1920 portrait, app-only imagery and motion, no field background or external device mockup.

## Core story

**Call it. Track it. Learn from it.**

The audience should understand three ideas in order:

1. A coach can call a pitch in seconds.
2. PitchMark records the result without breaking game flow.
3. Every call becomes useful performance data.

Do not try to explain every feature. Live sharing, runner advancement, and deep statistics support the main story; they are not separate tutorials.

## 45-second marketing film

| Time | Picture | On-screen copy | Motion / sound |
|---|---|---|---|
| 0:00–0:03 | Dark field at dusk. Chalk line catches light. PitchMark mark resolves at center. | **Every pitch starts with a decision.** | Low stadium ambience; one distant glove pop. Slow 2.5D push-in. |
| 0:03–0:07 | Floating iPhone enters. Games screen: select a game and pitcher. | **Set the game.** | Two deliberate UI focus pulses. Soft tactile ticks. |
| 0:07–0:14 | Pitch calling screen fills frame. The `Curve` button subtly grows; the rest of the UI dims. Strike zone then expands and one location highlights. | **1. Select the pitch** → **2. Tap the location** | Each instruction replaces the previous one. 8-frame button scale to 106%, then settle. |
| 0:14–0:18 | Called code appears large. Brief split view shows the receiving display. | **The call is shared instantly.** | Code lands with a clean digital click. No flashy transition. |
| 0:18–0:25 | Result screen: choose outcome, advance a runner, save the event. | **3. Record what happened** | Freeze for 8–12 frames at each decision. Outline only the active control. |
| 0:25–0:31 | Two devices float side by side; the second updates live. | **Everyone sees the same game. Live.** | Thin connecting line or traveling light; subtle sync chime. |
| 0:31–0:38 | Pitch cards sweep backward into a heat map and pitcher stats. | **Every call becomes insight.** | Cards compress into data points; music lifts. |
| 0:38–0:42 | Heat map, pitch breakdown, and spray chart cycle in one controlled composition. | **Patterns you can coach.** | Slow camera drift; no rapid montage. |
| 0:42–0:45 | PitchMark logo and App Store badge on dark field. | **Call smarter. Coach clearer.** | Music resolves; final glove pop. |

## 30-second App Store preview

Apple requires App Store previews to depict the app itself, so this version uses only captured PitchMark screens, app UI, labels, touch indicators, and app-derived graphic elements.

| Time | App footage | On-screen copy |
|---|---|---|
| 0:00–0:03 | Hero view of the pitch-calling interface | **Call every pitch with confidence** |
| 0:03–0:08 | Select `Curve`; tap a strike-zone location | **Select the pitch** / **Tap the location** |
| 0:08–0:12 | Called code appears; receiving display updates | **Share the call instantly** |
| 0:12–0:18 | Record the result and advance a runner | **Track the whole at-bat** |
| 0:18–0:22 | Live participant joins and sees the game update | **Follow the game live** |
| 0:22–0:27 | Cards transition to pitcher stats and heat map | **Turn every pitch into insight** |
| 0:27–0:30 | Strongest stats screen, then app-native PitchMark branding | **Call smarter with PitchMark** |

## Screen capture list

Record clean source takes with no narration, notifications, or hurried taps. Pause one second before the first action and two seconds after the last action. Repeat each take twice.

### Required recordings

- **R01 — Start a game:** Open game picker → choose prepared game → choose pitcher → return to tracker.
- **R02 — Call a pitch:** Tap `Curve` → tap a clear strike-zone location → allow code to appear.
- **R03 — Record a simple result:** Mark swinging strike or ball → save → show updated count/card.
- **R04 — Record ball in play:** Choose `In Play` → select `1B` or `2B` → select contact type → field location → save.
- **R05 — Advance runners:** Begin with a runner on base → advance the runner → save the play.
- **R06 — Live sharing:** Create invite → join on a second device → make one call on the owner device → show the receiving device update.
- **R07 — Pitch cards:** Scroll slowly through a short, visually varied pitch sequence.
- **R08 — Pitcher stats:** Open stats → hold on overview → reveal pitch-type breakdown.
- **R09 — Heat map:** Open a populated heat map → change pitch filter once → hold.
- **R10 — Game summary:** Open summary → show outcome breakdown and spray chart.

### Screenshot set

Screenshots let After Effects control pacing and focus precisely. Capture these in addition to recordings:

- Games picker with one clearly named demo game.
- Pitcher selected and ready.
- Calling screen before pitch selection.
- Calling screen with `Curve` selected.
- Calling screen with the intended location selected.
- Large called code visible.
- Result sheet before selection.
- Result sheet with a clean in-play result selected.
- Runner state before and after advancement.
- Live invite/join screen.
- Second-device live view.
- Pitch cards with 5–8 varied outcomes.
- Pitcher statistics overview.
- Pitch-type breakdown.
- Heat map with enough data to show a recognizable pattern.
- Game summary and spray chart.

## Demo data continuity

Use one fictional but credible game throughout so the film feels like one story rather than a collection of unrelated screens.

- Team: **Knights**
- Pitcher: **Juju #33**
- Batter: **#4**
- Inning: **4th**
- Score: **Knights 2, opponent 1**
- Count entering hero call: **1–1**
- Hero call: **Curve, low and away**
- Result: **swinging strike**

Avoid personal contact information, real join codes that remain active, TestFlight overlays, debug labels, and inconsistent scores/counts.

## After Effects build map

### Project structure

- `00_MASTER`
- `01_SCENES`
- `02_UI_CAPTURES`
- `03_PHONE`
- `04_BACKGROUND`
- `05_TITLES`
- `06_CALLOUTS`
- `07_AUDIO`
- `08_RENDERS`

### Reusable precomps

- **PM_UI_SCREEN** — replaceable screenshot or recording, cropped to the display.
- **PM_PHONE** — phone body, screen matte, glass reflection, shadow.
- **PM_FOCUS** — adjustable dim layer plus feathered cutout for the active control.
- **PM_TAP** — 18–24 frame touch ripple with optional click marker.
- **PM_LABEL** — numbered instruction with consistent entry/exit animation.
- **PM_OUTLINE** — soft green or blue highlight that follows a UI control.
- **PM_FIELD_DEPTH** — background, fence, dust/light layer, and foreground grass for parallax.

### Motion rules

- UI zooms: 100% → 106–112% over 10–14 frames with a soft ease.
- Button emphasis: 100% → 106% → 100% over roughly half a second.
- Focus dim: black at 22–32% opacity; keep the active control fully bright.
- Freeze holds: 8–15 frames before a label appears.
- Labels: 12-frame rise and fade; never bounce.
- Camera: slow and nearly invisible. One main movement per shot.
- Transitions: use match cuts, scale continuity, and screen wipes derived from app panels.
- Type: SF Pro or a close licensed substitute; short lines, sentence case.

## Visual treatment

- Background: night/dusk softball field, cool navy shadows, restrained warm stadium lights.
- Brand accents: use PitchMark green, red, and blue from the interface, one accent at a time.
- Phone: neutral graphite or natural titanium; avoid a glossy “ad mockup” look.
- Depth: shallow but readable. Never blur the actual interface being taught.
- Grain: subtle and confined to the cinematic background, not the UI.

## Audio plan

- Music: restrained pulse, 95–110 BPM, minimal melody during instruction.
- UI: soft tactile clicks, muted digital confirmations, very light whooshes.
- Sports texture: distant crowd bed, one glove pop at open and close, optional cleat-on-dirt sound.
- Mix priority: labels/voiceover first, UI second, music third, ambience last.

## Premiere assembly and exports

Use After Effects renders as complete scene modules. Premiere should handle ordering, final trims, music, sound effects, loudness, captions, and exports.

### Marketing master

- 1920 × 1080, 30 fps, progressive.
- Export a ProRes 422 HQ archive and an H.264 web version.
- Keep text inside a central safe area so a 9:16 social crop can be made later.

### App Store master

- 886 × 1920 portrait, 30 fps, progressive.
- Length: 15–30 seconds; target exactly 30 seconds or slightly under.
- H.264 target bit rate: 10–12 Mbps; stereo AAC at 256 kbps, 44.1 or 48 kHz.
- Maximum file size: 500 MB.
- Choose the poster frame intentionally; the default is at five seconds.

## Existing project assets worth reusing

- `AppStoreScreenshots/PitchMarkLive/01_Screen_1.png` — primary call/track screen.
- `AppStoreScreenshots/PitchMarkLive/02_Screen_2.png` — result capture and field map.
- `AppStoreScreenshots/PitchMarkLive/03_Screen_3.png` — pitcher stats and heat map.
- `AppStoreScreenshots/PitchMarkLive/04_Screen_9.png` — pitch-code explanation.
- `AppStoreScreenshots/PitchMarkLive/05_Screen_10.png` — setup, key creation, invite.
- `AppStoreScreenshots/PitchMarkLive/06_Screen_6.png` — scout/practice tracking.
- `AppStoreScreenshots/PitchMarkLive/07_Screen_7.png` — game summary and data.
- `PitchMark/Assets 2.xcassets/SoftballBaseballWtitle.imageset/softball baseball with title.png` — current brand mark source.
- `PitchMark/Assets 2.xcassets/field2.imageset/field2.png` — field graphic for app-derived transitions.

## Capture delivery structure

Place new material in this structure so replacements are quick and unambiguous:

```text
video-production/
  captures/
    recordings/
      R01_start_game_take01.mov
      R02_call_pitch_take01.mov
    screenshots/
      S01_games_picker.png
      S02_pitcher_ready.png
  audio/
  backgrounds/
  renders/
```

Use the labels from the capture lists above. Original full-resolution files should remain untouched; make crops and color adjustments only in the edit project.
