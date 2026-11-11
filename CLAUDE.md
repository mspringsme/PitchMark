# PitchMark

Two iOS apps in one Xcode project: **PitchMark** (the tracker the coach uses) and
**Pitchmark Display** (a second device that shows the called pitch to the player).
They share a Firebase project and most of the model layer.

## Building

Schemes are `PitchMark` and `Pitchmark Display` — note the lowercase `m` in the
Display scheme name, which does not match the `PitchMarkDisplay/` folder or the
`Pitchmark-Display-Info.plist` file. All three spellings are load-bearing; don't
"fix" them.

Command-line builds need code signing off, because signing the CocoaPods resource
bundles fails in a non-interactive shell (keychain access, not a code problem):

```
xcodebuild -scheme PitchMark -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Build both schemes after changing anything under `PitchMark/` — most of those
files are compiled into the Display target too (see below).

### Adding a shared file to the Display target

`PitchMark/` is a `PBXFileSystemSynchronizedRootGroup`, so new files land in the
PitchMark target automatically. They do **not** reach the Display target
automatically. `membershipExceptions` in `project.pbxproj` means "differs from
this target's default", which inverts depending on the target:

- Exceptions listed for the **PitchMark** target are *excluded* (currently just
  `Info.plist`).
- Exceptions listed for the **Pitchmark Display** target are *included*.

So a new shared file must be added by hand to the Display target's
`membershipExceptions` list, or Display fails to compile with "cannot find X in
scope". This is what `AtBatCount.swift` needed.

Conversely, a file that exists in both folders and is *also* listed there will
produce a duplicate-declaration error. This bit us once on `LearnPitchMarkView.swift`
during a merge — the resolution is to leave it out of the exception list.

## Verification constraints

**There are test targets now (2026-10-31) - see TESTING.md for the exact
commands and what's covered.** `PitchMarkTests` (unit, hosted in the app),
`PitchMarkUITests` (XCUITest, launches the demo game with `-UITestDemo`),
`PitchmarkDisplayTests`, and `rules-tests/` (Firestore emulator, needs
JDK 21+). The user's testing policy applies to every feature: tests before
"done", rules tests before any rules deploy, list the rules being tested
and get approval before writing tests, and break high-risk logic on
purpose to prove a test catches it.

- Logic buried in a view gets moved to a plain type so it can be unit
  tested (`GameProgress`, `PlayDraft`, `StatsEventFilter` are examples).
- New test files in a test folder join their target automatically (the
  folders are file-system-synchronized).
- Still manual: real two-device live sessions, real-device performance,
  and visual/feel checks. Ask the user for those; don't claim them.
- Screenshots of the running simulator do work and are worth taking for
  layout changes.

## The count (balls/strikes)

`AtBatCount.swift` is the single source of truth. Before it, five places computed
the count independently and disagreed — the main screen, the pitch result sheet's
live preview, the sheet's save path, scout mode, and the progress-adjustment path.
Symptoms were counts that changed depending on which screen you used.

Two rules that are easy to violate by accident:

1. **`PitchEvent.applyCount` is the only writer** of `atBatBalls`, `atBatStrikes`,
   and `atBatCount`. Never set those fields directly; the numeric pair and the
   display label must not be able to disagree.
2. **`atBatCount` is display-only and is never parsed back into a count.** On a
   terminal pitch it holds text like `"Ball 4"` or `"Strikeout"`, not `"3-2"`.
   The review step (`buildSavedPlayReviewedEvent`) goes through
   `applyCount` too (`PitchEventEdit.stampReviewedCount`); it used to write
   `"b-s"` by hand and turned every walk/strikeout label into `"0-0"`.
3. **Editing a saved pitch counts from the pitch before it**
   (`PitchEventEdit.countBefore`, passed as `countSeedOverride`), not the
   batter's latest pitch, and only an edit of the game's latest pitch moves
   the tracker's count. Later pitches keep their labels (user's choice).

In `PitchResultsSheetView`, the count is *derived* (`countSeed` + current
selection) rather than stored. The `.onChange(of: resolvedCount)` publisher is
gated on `isPresented` — without that guard, `resetSelections()` during sheet
teardown publishes the stale pre-pitch seed over the count that was just saved.
That regression is subtle and reproduced as a sequence like `["1-0","0-1","1-0"]`
with the main screen stuck at `0-0`.

## Stats

One rule per number, shared by every screen (batch 6, 2026-11-01):
whether a pitch ended an at-bat is `PitchEvent.atBatEnd`
(`AtBatCountRules.endOfAtBat`) for pitcher *and* hitter stats - don't
count strikeouts or walks by their K/ꓘ/Walk label alone, older pitches
carry none. Percentages go through `statPercent` (rounded, user's
choice). Strike/ball is `inferredPitchResultType`; hit-by-pitch is a ball.

## Firestore: things that will hang or clobber

**Never call `Firestore.terminate()` or `clearPersistence()`.** They block the
calling thread inside `FirestoreClient::Dispose`, and the C++ SDK reschedules
disposal onto the main queue regardless of which queue you call from — so moving
the call to a background queue does not help. This deadlocked the "Deleting
Account…" screen permanently; two thread dumps were needed to prove it. If
account-deletion cleanup ever needs re-doing, tear down listeners instead.

**Live progress uses `progressRevision`, a monotonic counter**, not a timestamp.
Comparing a Firestore `serverTimestamp` against a local `Date()` compares two
different clocks and lets a stale snapshot overwrite newer local state. Snapshots
are applied only when `remoteRevision > progressRevision`; the old timestamp
comparison is kept solely as a fallback for documents written before the counter
existed.

**`progressRevision` is server-assigned only — never increment it locally, and
never persist it across live rooms.** The number is minted inside
`commitLiveProgress`'s transaction, so a locally-invented counter compared
against it is comparing two different number spaces. The local guess runs ahead
in three ordinary ways: recording one pitch calls `markLocalProgressChange()`
three or four times in a single run-loop turn but those coalesce into **one**
publish (+N local, +1 server); any progress change made with no live room open
has no server counterpart at all; and a freshly created room has no
`progressRevision` field, so its first commit lands at 1 no matter how high the
old room got. Once local runs ahead, `remoteRevision > progressRevision` rejects
the partner's next N snapshots outright — ball/strike circles that fail to fill
in or fail to clear on the owner's device after a partner records a pitch.
Protecting a local change that hasn't reached the room yet is
`hasUnpublishedLocalProgress`'s job (a token pair, with a 5s grace window so a
publish that never reports back can't deafen the device permanently); it stays
out of the revision comparison. `progressRevision` resets when
`startListeningToLiveGame` sees a different `liveId`, and `LocalProgressSnapshot`
still writes the field but no longer restores it.

**Every live progress write must go through `markLocalProgressChange()`**, which
is what triggers the publish that earns a new revision. A write that lands in
`/liveGames` carrying no new
revision is ignored by the other device and then overwritten by the next write
that *does* carry one — so the change appears to stick and then silently reverts.
`updateCount`, `updateOuts` and `commitLiveProgressChange` are the three entry
points; nothing else should write balls/strikes/outs/inning/hits/walks/us/them.
`commitLiveProgressChange` defers the call precisely so it still runs on the
participant's early return.

**Never put an event's copies in one `WriteBatch`.** A pitch lives in up to three
places — `/liveGames/{id}/pitchEvents`, `users/{owner}/games/{gid}/pitchEvents`
and `/pitchers/{pid}/pitchEvents` — governed by three different rules. A
participant has *create-only* access to the owner's copy and cannot touch the
pitcher's. Batches are atomic, so one denial rejected the whole commit and the
edit/delete/undo landed nowhere, while the optimistic UI had already shown it as
applied. Use the `updateEventCopies` / `overwriteEventCopies` /
`deleteEventCopies` helpers in `CalledPitchRecord.swift`.

**The owner's device is the only bridge to the permanent record.** The live
pitchEvents listener mirrors `/liveGames` into the owner's game *and* the
pitcher's career collection, and it keys off `documentChanges` so `.modified`
and `.removed` propagate too — not just `.added`. Reverting that to "mirror each
id once" silently freezes the owner's copy at each event's first-written state.

`mirroredLivePitchEventIds` must be cleared in **`startListeningToLivePitchEvents`**,
not just in `startListeningToLiveGame` — that function restarts independently from
several call sites, a fresh listener replays the collection as `.added`, and a
surviving seen-set would skip exactly the edits made while it was detached.
Re-mirroring an unchanged event is an idempotent `setData`; losing an edit is not.

A `.removed` also has to be pruned from `seededGamePitchEventsForLive`, or
`mergeLiveAndSeededEvents` re-adds the deleted pitch from the stale seed array
and the card reappears on the next snapshot.

**A change to a saved pitch reaches the career records directly
(2026-11-01).** Edits, deletes, undo, pitcher moves and batter changes
plan their writes with `EventCopyTargets` / `EventCopyPlan`
(EventCopies.swift), which include `pitchers/{pid}/pitchEvents` and
`hitters/{hid}/pitchEvents`. Career stats read those, and the owner's
mirror only carries changes while a live room is open - so before this an
edit made after the game never reached them, and a pitch moved to another
pitcher vanished from both. An edit starts from the saved pitch and takes
only what the sheet answers (`PitchEventEdit.applying`); rebuilding it
field by field is how tracking mode, catcher's estimate, hitter link,
author, count and markers were lost.

**Knowing a document's id is never a credential (2026-10-31).** Joining a
live room (`participants/{uid}`), adding yourself to a pitcher's
`sharedWith`, and joining a team (`members/{uid}`) each require the write
to name a code or invite the rules can check: `joinCode`/`inviteToken`
(or `displayInviteToken`) for this room, unexpired; a pitcher invite for
this pitcher that you redeemed; a team invite for this team that you
redeemed, granting the roles you write. Invites are burned first, then
named. A partner's credential is remembered per room
(`LiveJoinCredential`) and in the joined-session bookmark, because
presence is deleted and recreated in ordinary use. App Store builds from
before this don't send it - **the rules can't be deployed until the new
build is out**, or partners on old builds can't join.

**Never put join codes or invite tokens on `/liveGames/{liveId}`.** That document
is readable by display participants and display-only sessions, which are meant to
render a called pitch and nothing else — a credential there lets a display device
rejoin as a full participant with write access to pitch events. They live in
`users/{uid}/liveSessions/{liveId}`, which is owner-only.

## Fielding stats (2026-11-03)

- **Each game pitch carries a copy of the defense** (`PitchEvent.defense`,
  stamped in `persistPitchEvent` from the pitching team's lineup cells and
  `Game.fieldPositionByBatterId`) plus `fieldingTeamId`. Credit goes to
  whoever held the position on *that* pitch - never read the game's
  current positions for stats, they change mid-game.
- Who fielded is `fieldingOuts` (one entry per out, fielders in order,
  last = putout) and `errorPositions`, answered on the result sheet's
  Fielded by row (`FieldedByView`). A strikeout is the catcher's putout
  and is never asked. Rules: `FieldingPlay` (shared with Display) and
  `FieldingLedger` (FieldingStats.swift, PitchMark only).
- Every rebuild of a pitch keeps them through
  `FieldingPlay.consistentOuts/consistentErrors` (review step, edit,
  save). The edit sheet starts from the saved fielders and its saved play.
- **Picking FC on the bases diamond puts the lead forced runner out**
  (`PlayDraft.fieldersChoiceRunner` / `batterCreditChanged`), unless a
  runner is already out; leaving FC puts them back. That out is what the
  Fielded by row asks about (6-4). One fielder = unassisted (6U / F8).
- The player sheet is "Player Stats" with Hitting and Fielding headers;
  every fielding table shows `FieldingStatsKey`. Its buttons say
  "Hitting & Fielding (Stats)" on Home and the roster, "Hit & Field" in
  the gear sheet's batter rows (the long label overflows that row).
- **RBI and R (2026-11-05)** come from each pitch's saved play
  (`HittingStatLine.runsBattedIn(for:)`). No RBI on ROE, on a play with
  2+ outs, or for a run tagged E/WP/PB; runner moves on a hit carry no
  reason, so a run an error helped still counts. R as a runner reads the
  game pitches' `basesBefore[from].hitterId` - hand-added runners credit
  nobody. Only a HR counts on a pitch saved before plays existed.
- Stats read the **owner's game pitchEvents** (fielding is on the other
  team's pitches, not in `/hitters`), so another coach's games don't
  count. No rules change was needed.

## Result sheet field (2026-11-04)

**There is one field.** The hit-location field (`FieldOverlayView`) is
never swapped out; the batter, runners, bags, credit chips and prompt are
`BasesFieldLayer`, drawn over it through its `overlay` hook at the bag
positions measured on FieldImage2 (`BasesFieldLayer.normalizedPoint`).
User's call - the separate diamond hid the hit marker, and a tap meant
for the field landed on a bag and made an Out batter safe. `fieldStage`
now only says whether the bags/prompt are live; with Out selected a bag
tap never places the batter.
The batter is always drawn (`batterToken`): dark, in their box at home
with "AT BAT" until placed, red "OUT" when out; runners are white. Runner
tokens take taps only once the batter's result is known, and the picked
runner lives in the sheet (`selectedRunnerBase`) so Refresh clears it.

## Team batting and the gear sheet (2026-11-05)

- **Team Batting Stats** (roster screen, beside Team Fielding) is
  `TeamBattingStatsView` / `TeamBatting` (TeamBattingStats.swift). It reads
  the team's games, not /hitters: the batting team is whoever wasn't
  `fieldingTeamId`; a pitch without one counts only for a linked roster
  batter. The Team row includes jersey-only batters and every run scored.
- **The lineup gear sheet never changes the game's batter.** Its
  highlight is its own (`viewedBatterId`, starting on the game's
  batter); notes, pitch cards, Order arrows and the action row follow it.
  User's call - looking at a player isn't picking them to bat. Don't wire
  a sheet tap back to `syncSelectedBatterFromDetail`.

## Home calendar, number-only players, result sheet (2026-11-05)

- **A number-only player is saved with the name "#12"** - no flag
  (`NumberOnlyName`, Utilities.swift). Every screen already reads it, and
  avatars show the whole number (`NumberOnlyName.avatarText`). The roster
  add form, Player Details and the in-game quick add all have the toggle.
  Changing a number-only player's jersey renames them to the new number,
  through the normal rename path.
- Home's Games header has a calendar button (`GamesCalendarView`); a game
  tapped there opens like its row.
- **The Safe/Out + Save Result row is sticky** (`StickyActionBar`): it
  stays in place until it reaches the top of whatever scrolls, then stays
  there while the field scrolls under it. The tracker wraps the card and
  the sheet in an *outer* ScrollView, so a pinned LazyVStack header inside
  the sheet never pins - the bar measures the divider above it in both
  named coordinate spaces (`outerScrollSpace`, set on the tracker's two
  wrappers, and `ownScrollSpace`) and offsets itself. A bottom
  `.safeAreaInset` was tried first and landed under the field.
  The catcher's pop-up button is "Skip".
- **The card's result box says each thing once** (`outcomeSummaryLines`):
  the play line is `BaseRunnerRules.cardSummary` ("2B", "1B + E · Safe at
  2nd · 1 run"), the stored outcome isn't repeated under it, and ball type
  + region share one line ("Line · Deep Right", "Hit" dropped on a hit).
  The box is ~3 lines tall; the spray chart reads these lines for color
  ("safe"/"1b".../"out"), so keep those words in them.
- **The review sheet's Save opens where Save Result was** (user's call:
  two quick taps in one spot). Save Result's global frame rides in the
  review draft (`saveAnchor`); `ReviewSaveLayout` puts Back + Save at
  that height, the title/count above only if they fit, the rest
  scrolling below. Track Game's Save Event passes no anchor, so its
  review keeps Back/Save at the bottom.
- **Home's Players + is `HomeAddPlayerSheet`**: team (teams you created,
  or No team = a bare player record), number only, name, jersey,
  positions, batting side. The old name-only sheet is Edit only.

## Scan Opponent Lineup (2026-11-06)

- **Home only, three places:** the new-game card (once an opponent team
  is picked; the reviewed lineup waits and is written when Save creates
  the game), an own game's ⋯ menu, and a joined live game's ⋯ menu (a
  partner). Rules: `LineupScan.swift` (parser, roster match, plan,
  route); reading: `LineupScanReader` (Vision, on device, image never
  saved); UI: `LineupScanSheet`; writes: `OpponentPartnerAccess.swift`.
- **Where it's written (`LineupScanRoute`):** no live room = the saved
  game, in one transaction, after quietly closing the game if it's open
  in the tracker (the tracker only reloads its lineup when empty, so it
  would save its older one back). An open room = the room, and the
  coach's phone also writes the saved game with the same spot ids.
- **Partners get the room's opponent roster** (rules: OPPONENT ACCESS FOR
  LIVE PARTNERS). The claim is `teams/{teamId}/partnerAccess/{uid}`
  naming the room; the rules re-check room open, partner in it, team
  still `awayTeamId` on every use. Read, add, edit name/jersey/positions/
  batting side; never archive or delete. The game's own team is
  **read-only** for partners (H1-H4, 2026-11-07) - claimed with
  `canEdit: false`, which never records a grant.
  A partner's new opponent player's Pitcher/Hitter/Player records are
  **the coach's** (`createdViaLiveId`), or the coach's phone couldn't
  save that batter's pitches (hitters are ownerUid-only). A partner
  rename names the row (`renamedVia`). Both live in
  `addTeamPlayerCreatingNewPlayer` / `PlayerDetailsSheet` behind
  `OpponentPartnerAccess.shared.grant(for:)` - don't add a third path
  that skips it. Partners never run `backfillRosterLinks`.
- **Real screenshots are mostly not lineup** (box scores: tabs, team
  names, stat columns, TB:/SB: footers). The parser marks
  `likelyBatter`; the review starts with only those kept and puts the
  rest under "Other text found" (`LineupReviewList`). Numbers right of a
  name are stat columns. The GameChanger fixture test is the check -
  run it after any parser change.
- **A partner loads the owner's game itself** (`loadGameForPartner`,
  once per room, off the room's `ownerGameId`): Home's rejoin and other
  join paths pass no game id, and without the Game a partner has no team
  ids - no rosters, no opponent claim, an empty gear sheet. The lineup
  cells stay the room's. Field positions ride the room too
  (`fieldPositionByBatterId`, whole map); a partner has every control
  except calling pitches.
- **Leaving a live game (2026-11-07):** the tracker's top menus have
  End Live Session… (coach's Key menu, opens the old dialog) and
  Disconnect (partner's mode menu); Home's ⋯ menus have the same
  (`HomeLiveLeave`, confirmed by `homeLiveLeaveDialog` at Home's root).
  Home's End looks the room up (`findOpenLiveRoom`) and only sets
  `status: "ended"` - every phone, the coach's own tracker included,
  acts on that. Home's Disconnect posts `activeGameShouldClose` only
  with a game id; without one it would close whatever game is open.
- **Lineup links ride the room** (`hitterIdByBatterId` on
  `/liveGames`, one dotted field per spot). `persistHitterLinks`
  publishes them; the coach's phone merges them in `applyRoomLineup`
  and saves links and the room's lineup to the game - only for
  server-confirmed snapshots. Before this a partner's Bench / Put In Game
  never reached the saved game.

## Tracker naming and memory (2026-11-02)

- **Coach/Scout are shown as "Call Pitches" / "Track Game"** and live in
  the Key menu (the assistant gets a mode menu of its own). The stored
  `TrackingMode` raw values stay `coach`/`scout` - every saved pitch
  carries them.
- **The tracker's top is two cards (2026-11-03)**, built in
  `pitchSelectionStrip`: who's pitching (Pitching side chips, pitcher,
  stats buttons) and what's thrown (Key menu - or the assistant's mode
  menu - and pitch chips). There is no separate top bar any more.
  The pitching card hugs its contents; the Key card gets the rest.
- **Gear sheet: Order arrows and field positions (2026-11-03).** Drag
  to reorder is gone; the Order arrows move the selected batter within
  their team. Each row's position button sets this game's position
  (`Game.fieldPositionByBatterId`, plain strings because the sheet is in
  the Display target; one per position per team, `LineupFieldPositions`).
  The field icon beside Order opens `FieldPositionsView`, which sets the
  same map through the same `assign` - don't give it a separate store.
- **Leaving a game remembers who was pitching and who was up, per side**
  (`TrackerSelectionMemory`, device-local). A partner in a live room
  follows the owner's room instead.
- **A player's name on Home is their oldest roster row's**
  (`PlayerProfile.name`), the same one the Edit sheet changes; a rename
  reaches every record the Player doc links (`PlayerLinks.renameTargets`).
  Picking the alphabetically-first Pitcher made Juju show as her old
  record's "Jug".

- **The tracker's `.onAppear` fires on every return to the Game tab**,
  not once - the boot flow (`handleInitialAppear`) runs only on the first
  (`LaunchHomeGate.claimFirstAppear`). Rerunning it re-applied the
  15-minute "start on Home" rule mid-session and bounced every trip back
  to the game straight to Home.

## Primary-device session (two devices, one account)

`users/{uid}/meta/activeSession` holds `deviceId` — whoever's id is there owns
primary. Three rules, each learned from the same multi-device bug report:

- **`ensurePrimarySessionOrPrompt` is asynchronous.** It is a Firestore read.
  Callers must use its completion, never test `showSessionConflictAlert` on the
  next line — that can't be true yet. Both the boot flow
  (`continueBootAfterSessionCheck`) and the scene-`.active` resume now hang off
  that completion. Getting this wrong let the boot sheets present first and the
  "Account In Use" blocker arrive underneath them.
- **Only `claimPrimarySession` may write `deviceId`.** `updateActiveSessionLiveId`
  used to stamp its own id in alongside `liveId`, which silently re-claimed
  primary as a side effect of publishing a live room — two devices then traded
  primary back and forth forever, each bouncing the other to Home.
- **The blocker is a root `.overlay`, so any sheet renders above it.**
  `requestGameConfirmation` bails while `showSessionConflictAlert` is set;
  anything else that presents a sheet needs the same guard, or it hides the only
  control that can resolve the conflict.

Concurrent callers of the check are queued (`pendingPrimarySessionChecks`), not
dropped — at launch `.onAppear` and the `isSignedIn`/`uid` `onChange` handlers
all fire within a frame, and dropping them would strand the boot flow.

## Live session lifetime

A room, its join code and its invite token all carry a 4h `expiresAt`
(`LiveGameService.sessionLifetime`). Past that mark the participant's listener
stops treating the room as active and called pitches silently stop arriving, so
the owner renews all three once inside `renewalWindow` (45 min), driven off the
live snapshot already in hand rather than a polling read. Renewing the *code*
matters as much as the room: `cleanupExpiredJoinArtifacts` deletes expired code
documents and `isActiveParticipantForThisGame` requires one to exist.

`endLiveSession` is the only writer of `status: "ended"`, and the participant's
live listener is what acts on it. The "End Live Session" button deliberately does
**not** clear `didAutoCreateLiveSessionForGameId` — clearing it let
`ensureAutoLiveSessionIfNeeded` spin up a new room on the very next called pitch,
silently undoing a destructive action. Re-inviting has its own path:
`CodeShareSheet`'s Generate button calls `createLiveGameAndJoinCode` directly.

**`outs` syncs through the live room only.** `Game` has no `outs` column and one
was not added — outs are inning-scoped. But because `outs` rides in the published
progress snapshot it must also stay in `LocalProgressSnapshot`, or a relaunched
device restores its old revision, skips the room snapshot as not-newer, keeps
outs at 0, and republishes that 0 over the other device's real count.

## Archive, never delete

Games, teams and players are never deleted from the app - stat history is the
product. Each has an archive instead:

- **Game:** `Game.archivedAt` on the owner's game. Archiving asks whether the
  game still counts in *this viewer's* stats (both teams, that game only);
  the answer lives in `users/{uid}/meta/statsPreferences` and stays
  changeable. Every stats screen goes through `AuthManager.gameCountsInStats`.
- **Team / player:** per user, in `users/{uid}/meta/archive` (`teamIds`,
  `pitcherIds` - players are keyed by Pitcher id). Hide-only; never touches
  stats. Per user because teams are shared between coaches.
- **Roster row:** `TeamPlayer.archivedAt` - team-level, creator-only, shown
  under the roster's Show Removed with Restore.

Real deletes remain only for account deletion (server-side), individual pitch
events (undo/corrections), a bare jersey number in a lineup, and Merge
Duplicates' cleanup of rows/records it has folded into another profile.
`firestore.rules` denies deleting a team document outright.

**Nothing on the open game's teams can be archived.** While a game is open in
the tracker, `OpenGameLock` (SettingsView.swift) refuses player archive,
roster Remove and Archive Team for either side's team, and offers Close Game.
Merge Duplicates (and Link when it combines profiles) is locked the same way,
because it removes the extra roster row (batch 7, user's choice).
Unarchive and Restore are never locked. Every new archive path needs the same
check.

**Merge cleanup deletes only on certainty (batch 7, 2026-11-01).** The
decisions live in `ProfileMerge` (ProfileMerge.swift); the AuthManager code
carries them out. Nothing is deleted if any team's roster read fails
(`loadTeamPlayersResult` - plain `loadTeamPlayers` turns a failure into
`[]`, which made that team's references invisible). A Hitter's history is
its pitches *and* its runner events (a pinch runner's steals). A `Player`
doc's `linkedPitcherIds`/`linkedHitterIds` move onto the kept player before
the doc is deleted, or it stays.

**A player archive hides them from games, so it must never be silent.**
Every archive confirms with the names `ArchiveScope` reads off the roster
rows - more than one name means kids share records. The team roster marks
archived players (swipe right to unarchive) and the lineup sheet names who
it left off the bench. Do not migrate the old device-local `hiddenPitcherIds`
into the account archive: it meant "hide from the pitcher picker", and
converting it (2026-10-26) silently pulled five kids out of a roster's games.

## Dialogs

Use `appConfirmationDialog` (in `SupportExtensions.swift`), not SwiftUI's
`.alert()`. `dynamicTypeSize()` has **no effect** on `.alert()` because it is
backed by `UIAlertController`, so alerts get horizontally squeezed at large
accessibility text sizes. There are ~24 call sites; keep new ones consistent.

**Attach it at the root of the sheet or screen, never to a small subview.**
SwiftUI clips an overlay's hit-testing to its parent's frame, so a dialog
attached to a button row renders full-screen but only accepts taps inside that
row — every other tap falls through to whatever is underneath. The Sign Out
dialog had exactly this bug: confirming it opened the Delete Account sheet.

## SwiftUI gotchas hit in this codebase

- **`Menu` loses scroll position.** Its contents are a transient `UIMenu`,
  regenerated whenever the parent re-renders — and the cards sheet re-renders
  constantly from Firestore listeners. The filter UI is a sheet-hosted `List`
  for this reason; `List` keeps its offset across body updates.
- **`.fixedSize(horizontal: true)` on the tracker's control buttons pushes
  content off-screen** by forcing full intrinsic width. Use
  `.frame(maxWidth:)` + `.layoutPriority(1)` instead.
- The tracker's `ScrollView` fallback is **unconditional**. It used to be gated
  on `height <= 700`, which left iPhone 17 (874pt) bleeding past the safe area
  top and bottom while iPhone 17 Pro Max (956pt) looked fine.
- **Launch crash in `swift_getTypeByMangledName` / `resolveOpaqueType` /
  `_findExtendedTypeContextDescriptor` / `buildDescriptorPath`.** Hit **eight
  times** across `undoButtonOverlay`, `resetButtonOverlay` and
  `batterSideOverlay` — all members of `PitchTrackerView` consumed deep inside
  `strikeZoneArea`.

  **What does not work** (five failed attempts, don't repeat them): wrapping
  the chain in `AnyView` once; declaring the member's type `AnyView` instead of
  `some View`; wrapping at the call site; erasing to `AnyView` after *every*
  modifier; pre-warming the member at the top of `body` with `_ = foo`. The
  decisive evidence against all of it: `batterSideOverlay` was **already**
  returning `AnyView`, already fully erased internally, and crashed anyway.

  **What works: make it a top-level `View` struct.** The runtime is not
  choking on chain length — it is walking the *enclosing type's* descriptor
  path, and the enclosing type is a 14,500-line view with a huge generic/opaque
  context that every `some View` member declared inside it inherits. A
  top-level struct's body is a small concrete type with none of
  `PitchTrackerView` in its mangled name. `StrikeZoneCard` — the card these
  five decorate — was always a struct, and never once crashed.

  The five strike-zone overlays are now `ZoneOpponentLabel`, `ZoneResetButton`,
  `ZoneUndoButton`, `ZoneGameStatsButtons` and `BatterSideOverlay`, declared at
  file scope. Keep new strike-zone decorations structs too, and don't move
  them back — but read the next entry before wiring one up.
- **Launch crash at `___chkstk_darwin`, naming a different function every
  build** (`strikeZoneArea`, then `confirmSheetBinding.getter`, …). This is
  stack *exhaustion* across the whole render path, **not** one oversized
  function — which is why "fixing" the named function only moves the crash to
  the next one. Do not chase the named frame.

  Measured on the arm64 device object (`otool -tV`, `sub sp, sp, #imm` in each
  prologue) rather than guessed:

  | | at HEAD | after a big feature session |
  |---|---|---|
  | `assignWithCopy value witness for PitchTrackerView` (≈ the struct's size) | 3136 B | 3232 B |
  | `PitchTrackerView.body.getter` frame | 2032 B | 2208 B |
  | functions emitting a stack probe | **0** | **0** |

  So: **no single frame in this file exceeds 4 KB in Debug or Release**, and
  `confirmSheetBinding.getter` — which one crash report named — is a *160-byte*
  frame. The cost is spread across a ~150-frame AttributeGraph chain, and every
  copy of the view costs ~3 KB because `PitchTrackerView` is a ~3 KB value.

  Useful commands for the next person:
  ```
  xcodebuild -scheme PitchMark -destination 'generic/platform=iOS' \
    -derivedDataPath DD CODE_SIGNING_ALLOWED=NO build
  xcrun otool -tV DD/.../arm64/PitchTrackerView.o | grep -E 'sub\s+sp, sp, #0x'
  ```

  **Confirmed 2026-10-21 by the exception type**, which is the one piece of
  evidence that settles it: `EXC_BAD_ACCESS (code=2, address=0x16b40bff8)` —
  code 2 is a protection failure and the address is in the stack region, i.e.
  the guard page. It is a stack overflow, and it is **intermittent** (same
  build sometimes launches, sometimes dies) because the app sits right at the
  limit. Ask for the exception type before theorising; a bare backtrace names
  a different innocent function every run.

  **The cause is the size of `PitchTrackerView` itself.** It declares **267
  `@State` properties** (273 property wrappers total), which is what makes the
  struct a ~3.2 KB value — and the crashing frame is always `outlined init
  with copy of PitchTrackerView`, i.e. that 3.2 KB being copied onto the stack
  again. The render path copies it many times over.

  Things that measurably do **not** help: AnyView erasure, pre-warming at the
  top of `body`, and moving `self`-capturing closures out of a parent's frame.
  The lever that does work is making `PitchTrackerView` smaller.

  **Step 1 done (2026-10-21):** 153 presentation-state properties (Bool flags,
  `String = ""` text entry, `String? = nil` ids) moved out of `@State` into
  `TrackerUIState`, an `ObservableObject`. Measured on the device object:

  | | before | after |
  |---|---|---|
  | struct size (`assignWithCopy` witness) | 3232 B | **1120 B** (−65 %) |
  | `body.getter` frame | 2208 B | 3808 B (+1600) |
  | largest frame in file | 3408 B | 3808 B (still < 4096 probe) |

  Net win: every copy on the render path is 2112 B cheaper, against a one-time
  +1600 B in `body`. `PitchTrackerView` keeps a same-named forwarding computed
  property for each moved value (`get { ui.x } nonmutating set { … }`), so the
  ~1050 plain `foo` references needed no edit — only the 94 `$foo` binding
  sites became `$ui.foo`. Invalidation granularity is unchanged: `@State` on
  this view already invalidated all of it, and one `@Published` object does the
  same. Note `@Published` must be written on the main thread, same as `@State`.

  **Still owed if headroom is short:** `body` is a 766-line chain with 31
  presentation modifiers — splitting it into segment properties would move its
  3808 B into separate frames. Remaining `@State` on the view: ~110 (arrays,
  dictionaries, model types).

- **Home (SettingsView) has its own depth limit: generic type nesting.**
  `EXC_BAD_ACCESS code=2` inside `decodeMangledType` / `decodeGenericArgs`
  (dozens of alternating frames), raised from a `SettingsView` section getter,
  is the runtime recursing through one enormous concrete view type until the
  stack runs out. Unlike the PitchTrackerView entry above, `AnyView` *does* fix
  this one, because the problem is the depth of the type itself. `gameRow` and
  `gamesOverviewSection` return `AnyView` for this reason (2026-10-27, crashed
  tapping Home from a game). A row helper reused by several `ForEach`es is the
  first thing to erase.

## Grid key printing (2026-11-08)

- **One place owns print size:** `GridKeyPrintSize.swift` (the size
  type, `GridKeyProduct` sizes and custom limits, a key's own size -
  shared with Display, because AuthManager saves and loads it),
  `GridKeyPrint.swift` (`fitScale`/`writePDF`, PitchMark only) and the
  server twin `functions/src/gridKeyPrintSize.ts`. The store preview, the
  free PDF and the fulfillment PDF all go through it - keep the two files'
  sizes and limits identical. A PDF page is 72 pt per inch, so a page
  `size.points` big prints at exactly that size.
- **A custom size rides the order:** checkout sends
  `printWidthInches`/`printHeightInches`, the server validates them (3-7 x
  2-5 in, quarter inches), puts them in Stripe metadata and saves them on
  `retailOrders`. Never fall back to a standard size - every Custom order
  used to print at 5 x 3. The server refuses a Custom order with no size
  (user's call), so deploy functions before the app that sends it.
- **Fit is measured, not just estimated:** `fitScale` starts from
  `baseContentSize` and shrinks until the real render fits. Spacing inside
  `PrintableEncryptedGridsView` must go through `s()`; an unscaled 8 pt
  gap ran cards 2-5% past their edge.
- **A pitching key has its own size (2026-11-10)**, picked in its
  editor (Width/Height, the same 3-7 x 2-5 in quarter-inch choices as a
  Batting card), saved as `printWidthInches`/`printHeightInches` on the
  template (optional - older keys print at the 5 x 3 default). The store
  sells **one** "Pitching Key" item ($14, `grid_custom`) at the key's
  size (`RetailCheckoutRequest.gridKey`) - no size pickers. `grid_5x3`
  and `grid_3_5x2_75` stay on the server for older app builds.
- The 8.5 x 11 sheet shrinks rows once pitches would overrun a block (8+
  pitches ran off the page). No cut guide is drawn on fulfillment PDFs.
- `functions/lib` is checked in and deploy ships it as-is: run
  `npm test` (or `npm run build`) in `functions/` after any `src` change.

## Batting Bases & Fielding grids (2026-11-08, several grids 2026-11-09; was Batter & Runner Grids)

- **A sign card the coach builds from scratch** (`SignGrid.swift` = model,
  layout, PDF, store; `SignGridViews.swift` = Home section, editor). A card
  is 1-9 grids pieced together (like a wristband card), all sharing the
  card's 1-12 rows and columns, free text per cell (24 chars). Print size
  is the **whole card**, with the custom grid key limits (3-7 x 2-5 in,
  quarter inches). The arrangement (across x down) is picked
  automatically from the card size (`SignGridArrangement.bestFit`); the
  editor's wireframe and the PDF use the same `SignGridCardLayout`.
- **Styles are B (bold) and F (fill), N clears both.** Each grid has its
  own fill color (2026-11-10; the picker sits between the Row and Col
  styles). A grid with none - every grid on a card saved before then -
  uses the card's `fillColorHex`, which is also new grids' default.
- **New cells come numbered** (`SignGrid.headerLabel`): the top row is
  the grid's digit + column ("01 02" on grid 1, "11 12" on grid 2), the
  first column 1, 2, 3, the corner blank; columns past 9 get none (user's
  call). Only new cells (new card, grid, row, column) are numbered -
  loading never renumbers, and a grid holding only its numbers removes
  without asking.
  A cell's own style overrides its row and column (user's call); with
  none, it's row + column together. Styling a row or column again
  resets its cells' own styles - the latest change wins.
- Saved at `users/{uid}/signGrids/{id}` (the users/** catch-all rule; no
  rules change). `grids` is an array of maps; cells are flat row-major
  arrays and styles arrays of maps - Firestore crashes on nested arrays.
  Docs saved before 2026-11-09 (one grid, `boldRows`/`boldColumns`/
  `boldCells`) load as a one-grid card. Archived, never deleted.
- Styles are `[Int: SignGridStyle]` so the JSON snapshot (checkout
  fingerprint) encodes them in a fixed order - don't key them by a struct.
- **The PDF is vector** (`ImageRenderer.render` into a PDF context), one
  page exactly the chosen size. Tests read text, bold and fill back off it.
- **Store product `sign_grid_custom`**, $20 for 14 cards (user's call),
  priced in code (`price_data`, no Stripe price object). It's sized like
  `grid_custom` on the server and in `GridKeyProduct.isCustom`; itemKind
  `signGrid`; fulfillment decodes the snapshot as a `SignGrid`.
- **The checkout fingerprint includes a hash of the design**, so an edited
  key or grid ordered again in the same session gets a new Stripe session
  instead of the first one's saved copy (that used to print the old key).
- **Quick Fill** (under the cell text box) puts a common call's short
  label in the selected cell (`SignGridQuickFill`, the user's list); the
  cell stays selected. It's a List in a sheet, not a Menu (scroll loss).
- **My Calls (2026-11-10):** while a cell is being typed in, a bar on
  top of the keyboard has **Add to Quick Fill** - a bottom
  `.safeAreaInset`, not a keyboard toolbar (that floats over the B F N).
  Added calls are the account's (`users/{uid}/meta/signGridQuickFill`,
  the meta rule; `SignGridMyCalls`/`SignGridMyCallsStore`,
  SignGridMyCalls.swift), shown first in Quick Fill and swiped away
  there. No repeats of a built-in or own call, ignoring case.
- **Randomize** (Whole Card section) fills only the **empty** call cells
  on every grid (user's call) with the Quick Fill calls the coach picks,
  spread evenly (each within one use of the others) in random cells
  (`SignGrid.randomFill`). Typed cells and the numbers are kept; the
  picks stay while the editor is open.
- The keyboard's hide button is in the top bar: a keyboard toolbar button
  floats over the cell's B F N. UI tests open the list and editor alone
  with `-UITestSignGrids`.

## Coach's calling card (2026-11-10)

- **Each Batting Bases & Fielding card has a calling card**
  (`SignGridCallingCard`, SignGridCallingCard.swift): every call on the
  armband card, A to Z (user's call), with the number of every cell it's
  in. A number is the cell's **column header + row header** from its own
  grid ("13" + "2" = "132"), read from the cells, so edited headers
  carry through; a cell with no header number isn't listed (columns past
  9 have none) and the card says how many.
- The list row's numbered-list button opens it (`SignGridCallingCardSheet`)
  with Share/Print: one US letter page, shrunk to fit. **Store orders
  print it as page 2** of the fulfillment PDF (`writeOrderPDF` →
  `includingCallingCard`); the free card PDF stays one page. No server
  change - it's built from the same snapshot.
- **Two sizes (2026-11-10):** Share asks Full Page (8 1/2 x 11) or
  Pocket (4 1/4 x 5 1/2, a quarter sheet) - `SignGridCallingCardPrint.Format`.
  **The store preview is drawn the way it prints**
  (`SignGridCallingCardPagePreview`, same margins and `layout(for:format:)`)
  - laying the card out freely let a big card run past its box.
  **A card too tall for its page is laid out wider and shrunk back to
  the page's width** (`SignGridCallingCardPrint.Layout`: columns, layout
  width, fit), so it always fills the width; it may also take up to 2
  more columns. **Every box is the same height**: numbers in even lines
  (`codesPerLine`), every box padded to the most lines any box needs,
  every label one size on a band of one height. The height is worked
  out (`SignGridCallingCardView.height`), not rendered - rendering to
  measure inside the search took minutes on a big card; a test checks
  it against a real render.
- **Store: Waterproof Calling Cards**, `calling_card_waterproof`, $8 for
  4 pocket cards the user cuts from one letter sheet (user's call),
  priced in code. Same snapshot as a grid order (itemKind `signGrid`), no
  size. Fulfillment prints one letter page with the pocket card in each
  quarter (`sheetQuarters`), no cut guides (user's call). New catalog
  entry in `functions/src/retailCatalog.ts` - deploy functions first.
- **Return in the cell box skips the numbered top row and first column**
  (`SignGrid.cellAfter`); typing a call into a number broke that row's
  codes. Tapping a number cell still edits it.

## Home's row of three (2026-11-10)

- **Team Supplies, Join a Game, Account** sit side by side, pinned at
  the bottom of Home just above the signed-in line (`HomeBottomBar`, a
  `.safeAreaInset`; the cards scroll under it), each with
  the `SoftballAndBaseball` art. Team Supplies is the store; Join a Game
  is the old top-bar button's flow (`startJoinFlow`, Pro only); Account
  opens the account sheet. Home has no toolbar items now. The header is
  the PitchMark logo, centered (`SettingsView.logoImageName`), not text.
- **"Armband Keys"** (under a divider) heads **Pitching** (was Code Grid
  Keys; the tracker's button says "Open Pitching Keys") and **Batting
  Bases & Fielding** (was Batter & Runner Grids, also in the store).
- The bottom of Home is plain text, "Signed in as {email}"
  (`HomeSignedInFooter`), read from `authManager.user` so it follows
  sign-in and sign-out. It is not a button.

## Known open items

- **HBP cannot be saved on its own.** Save Result is gated on one of
  Swinging/Looking/Foul/Ball/Hit being selected, and HBP is none of those.
- **Cancelling the pitch composer leaves the previewed count on the main
  screen.** Pre-existing, not caused by the count rework.
- **`atBatPulse` re-renders the whole tracker every 0.8s** when no batter is
  selected. Real performance defect, not yet addressed.
- `atBatCountCacheByBatter` is retained deliberately — it is not dead code.
- **Mixed-version live sessions still carry the old bugs.** An App Store build on
  either side of a room behaves as before: an old *partner* writes hits/walks
  without bumping `progressRevision` so the owner ignores them, and an old *owner*
  mirrors each event only once so partner edits never reach the permanent record.
  Neither is a regression — don't read a failed two-device test as one when a
  device is on the store build.

## Working agreements

- The user commits and pushes from Xcode. Don't push.
- Prefer one conversation per task, ending at a verified build + commit.
