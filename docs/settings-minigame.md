# Settings Minigame Concept

## Summary

Add a small optional minigame inside the settings experience. The user tilts their phone to move a group of baseballs and softballs around a bounded playfield. Randomly placed holes capture the balls. Each ball can represent a sponsor or brand. When a round ends, the app shows a short winner banner such as `Rawlings wins!` and presents a tappable destination for that sponsor.

## Product Goals

- Add a playful moment to the app without interfering with core scorekeeping flows.
- Create a reusable branded surface that can later support sponsorships or promotions.
- Keep rounds short, understandable, and visually satisfying.

## Core Gameplay

1. The settings view contains a fixed-size play area.
2. A set of baseballs and softballs spawn inside the play area.
3. The device tilt controls gravity using motion input.
4. Balls roll and collide with each other and the walls.
5. Randomly placed holes capture balls when they fall in or settle over them.
6. The app tracks captures by brand.
7. At the end of the round, the leading brand wins and a short banner appears.
8. The banner can open a sponsor URL, sponsor sheet, or branded detail view.

## Round Rules

- Holes should be placed randomly within safe margins so they never overlap the edges.
- Balls should spawn away from holes to avoid immediate captures.
- A round can end after a time limit, after all balls are captured, or after a minimum capture threshold is reached.
- Ties can show `Tie game` or prefer the first brand to reach the high score.

## Brand Model

Each branded ball should support:

- `id`
- `brandName`
- `imageAssetName`
- `destinationURL`
- `weight` or `spawnCount`
- optional `campaignId`
- optional `accentColor`

This allows future sponsor inventory to be rotated, weighted, or targeted.

## UI Behavior

- The minigame should live in its own card or panel inside settings.
- It should not block access to actual settings controls.
- The banner should appear briefly and stay tappable while visible.
- There should be a clear dismiss or replay path.
- Motion should be disabled or reduced when `Reduce Motion` is enabled.

## Technical Direction

Recommended approach: `SpriteKit` embedded in SwiftUI.

Reasons:

- Better fit for rolling balls, collisions, and hole capture behavior.
- Easier to tune gravity, damping, restitution, and boundaries.
- Easier to keep the minigame isolated from the rest of the settings layout.

Likely structure:

- `SettingsMiniGameView.swift`
- `BallPitScene.swift`
- `BrandedBall.swift`
- `MiniGameResultBanner.swift`

## Motion Input

- Use `CoreMotion` to read gravity or attitude from the device.
- Convert tilt into scene gravity.
- Clamp the values so the balls do not move too aggressively.
- Pause motion updates when settings is dismissed or backgrounded.

## Capture Logic

- Holes can be implemented as sensor regions rather than literal physics voids.
- When a ball enters a hole radius and remains slow enough, mark it as captured.
- Remove or fade the captured ball from active simulation.
- Increment that brand's score.

This should feel deliberate instead of letting fast-moving balls disappear unfairly.

## Monetization Path

Future sponsor support could include:

- branded ball textures
- branded winner banner
- sponsor tap-through destination
- campaign rotation
- impression and tap analytics
- optional cooldown rules to avoid showing a sponsor too often

## Risks

- The settings screen may feel cluttered if the game is too large or too animated.
- Device motion in a scroll-heavy screen can feel noisy if not carefully bounded.
- Sponsor integration should stay clearly secondary to the core app experience.
- External links and ad-like behavior should be reviewed against platform policies before launch.

## Suggested MVP

- One fixed playfield in settings
- 10 to 20 balls
- 3 to 5 random holes
- 2 or 3 mock brands
- short 10 to 15 second round
- winner banner with mock CTA
- no real ad serving yet

## Open Questions

- Should the game appear every time settings opens, or only occasionally?
- Should a round start automatically or require tap to begin?
- Should brands be purely cosmetic at first or already backed by a simple campaign model?
- Should the CTA open Safari, an in-app sheet, or a sponsor detail screen?
- Should the user be able to replay immediately?

## Next Step

If this moves toward implementation, the first build should be a non-sponsored prototype with placeholder brands and a contained `SpriteKit` scene. That will validate feel, performance, and whether the settings screen is the right location before any advertiser workflow is added.
