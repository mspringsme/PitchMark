# Moments roadmap

The log of Moments ideas from the 2026-11-15 review, and where each one
stands. Moments is a main competitive edge over GameChanger: its editing
is deep, and only PitchMark has pitch-level game data to tie clips to.
Update this file as items ship.

## Done (2026-11-15)

- **Clean-up:** opens on All; tapping a clip opens it; long-press menu
  (Play, Share, Move, Duplicate, Duplicate Original, Delete); ⋯ menu on a
  clip's screen (Move, Duplicate, Duplicate Original, Revert to Original,
  Delete); edit buttons grouped (Clip / Look / Add) with icons and an
  "applied" mark; no Done button on the tab; filter chips (All, Favorites,
  Videos, Photos, This Week); Duplicate keeps title, favorite, folder,
  photos, game and players; Highlight Reel renamed **Mixtape**, with its
  own button.
- **Photos backup on by default.** It had been silently doing nothing:
  add-only Photos access can't see or make the "PitchMark" album, and the
  save required the album. It now saves without it. Imports aren't copied
  back to Photos; in-app photos are backed up as photos.
- **Game caption:** a clip or photo captured while a game is open
  remembers the game (inning, count, outs, score, batter, pitcher, game,
  date). The coach is asked which items to show along the bottom, for how
  long (3/5/10 sec or the whole clip), and whether to fade out. **Game
  Info** on the clip's screen changes or removes it later.
- **Player clips (#3):** clips are tagged with the batter and pitcher from
  the game, or by hand (Players on the clip's screen). A Moments button
  (video icon + count) on the player's row in Home's Players list and on
  team rosters opens their clips - moved off the stats sheets (user's
  call). The library has a Player filter.
- **Compare (#5):** pick two clips, line each up (scrub, frame step, Set
  Sync Here), frame each one (pinch / drag / zoom slider, double-tap to
  reset), then play them together locked at those points at ¼×, ½× or
  1×, frame by frame, looped, stacked or side by side. Start Here / End
  Here cut the length. **Save** makes a new Moment with the framing,
  layout, Start-End and speed (sound only at 1×).

## Not yet built

1. **Record from the game screen.** A camera button in the tracker that
   records without leaving the game. Clips would be tagged with the exact
   pitch, not just the game state when recording stopped. (The user chose
   to keep recording in Moments for now.)
2. **Tie a clip to its pitch.** Store the pitch event id on the Moment,
   so the pitch card can show "has video" and the clip can show the pitch
   result ("Strikeout swinging", hit location).
3. **Pitch "stat bug" styles.** More caption looks than the current
   two-line text: a TV-style score bug, team colors, a pitch-result
   badge.
4. **Automatic Mixtapes.** "Kenzie's strikeouts this season" built from
   tagged clips plus their pitch results. Needs #2 for the results.
5. **Cloud storage for videos (Pro).** Upload clips to Firebase Storage
   so they survive a lost phone and show on every device. Costs per GB.
6. **Family share links.** A link that plays the clip in a browser, no
   app needed. Needs #5.
7. **Compare extras.** Drawing (Markup) on the compare screen; an
   overlay ("ghost") mode with one clip see-through on top of the other;
   more than two clips; a caption naming each side in the saved video.
8. **Record button label (D).** The Record button is icons only (video
   and camera); give it the word "Record". Left out of the 2026-11-15
   batch.
9. **Caption on imported clips.** Imported videos aren't asked about game
   info (they may be from another day). Game Info works on them when a
   game is open, but uses the open game's state, not the clip's.
10. **Bulk actions.** Select several clips to move, favorite or delete
    at once (selection is only for Mixtape and Compare today).
