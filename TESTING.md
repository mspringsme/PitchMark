# Testing

Three kinds of automated tests, plus a short list of things only a person
can check. Policy: nothing is "done" until its tests are written and the
whole suite passes (see the testing policy in the project memory / CLAUDE.md).

## Running everything

From the repo root. `DEVELOPER_DIR` is needed because `xcode-select` points
at the Command Line Tools on this machine.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# PitchMark: unit tests (PitchMarkTests) + UI tests (PitchMarkUITests)
xcodebuild test -scheme PitchMark \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# Pitchmark Display: unit tests (PitchmarkDisplayTests)
xcodebuild test -scheme "Pitchmark Display" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# Cloud Functions helpers (node:test, builds lib/ first)
cd functions && npm test && cd ..

# Firestore rules, against the local emulator (needs JDK 21+, see below)
cd rules-tests && npm install && npm test
```

Faster subsets:

```sh
# unit tests only (seconds once built)
xcodebuild test -scheme PitchMark ... -only-testing:PitchMarkTests
# one UI test
xcodebuild test -scheme PitchMark ... -only-testing:PitchMarkUITests/RunnersPanelUITests/testStealSecond
```

Don't pipe `xcodebuild test` into `head` - closing the pipe kills the run.
Send it to a log file and grep that.

### Rules tests prerequisites

- `firebase-tools` (installed globally) and Node 20+.
- **JDK 21 or newer** - the Firestore emulator refuses older Java. A
  Temurin 21 JDK lives in `~/Library/Java/JavaVirtualMachines/jdk-21.0.13+9`
  (added 2026-10-31); `npm test` selects it with
  `JAVA_HOME=$(/usr/libexec/java_home -v 21)`.
- The emulator runs on port 8085 under the fake project
  `demo-pitchmark-rules`, so it never touches the real database.
  `rules-tests/firebase.json` is separate from the root one on purpose.
- **Run these before any `firebase deploy --only firestore:rules`.**

## How the test targets are set up

| Target | Kind | Host | Notes |
|---|---|---|---|
| `PitchMarkTests` | XCTest unit | PitchMark.app | `@testable import PitchMark` |
| `PitchMarkUITests` | XCUITest | PitchMark.app | launches with `-UITestDemo` |
| `PitchmarkDisplayTests` | XCTest unit | Pitchmark Display.app | `@testable import Pitchmark_Display` |

Folders are file-system-synchronized: a new `.swift` file in a test folder
joins its target automatically.

**`-UITestDemo`** (handled in `PitchMarkApp`) opens the local demo game
directly: no sign-in, nothing written to Firestore, Home ("Us") pitching,
one lineup batter `#1`. UI tests find controls by accessibility identifier:
`runners.bag.{1,2,3}` (value = runner label or `empty`), `count.{B,S,O}.{i}`
(value `on`/`off`), `score.home` / `score.away` (value = runs),
`runners.actions`, `runnerPicker.add`.

**`-UITestSignGrids`** opens Batting Bases & Fielding grids alone (list + editor,
in memory, nothing written): `signGrid.new`, `signGrid.name`,
`signGrid.{rows,columns,grids}.{minus,plus,value}`, `signGrid.currentGrid`,
`signGrid.previousGrid` / `nextGrid`, `signGrid.wire.{index}` (the whole-card
wireframe), `signGrid.cell.{r}.{c}` (value = cell text), `signGrid.cellText`,
`signGrid.style.{row,column,cell}.{b,f,n}` (value `On`/`Off`), `signGrid.fillColor` (the current grid's color),
`signGrid.keyboardDone`, `signGrid.quickFill` (rows `signGrid.quickFill.{label}`), `signGrid.save`, `signGrid.row.{name}`,
`signGrid.callingCard.{name}` (opens the calling card: `callingCard.call.{label}`, `callingCard.share`, `callingCard.done`),
`signGrid.addToQuickFill` (on the keyboard), `signGrid.randomize` (sheet: `signGrid.randomize.pick.{label}` value `On`/`Off`, `signGrid.randomize.fill`).

`HomeLayoutUITests` uses the real Home through Skip for Now (demo mode):
`home.logo`, `home.armbandKeys`, `home.section.pitching`, `home.section.batting`. It also opens the store
from Team Supplies and finds Waterproof Calling Cards (`store.callingCard.title`)
and the one Pitching Key item (`store.gridKey.printsAt`), and opens a new
pitching key's editor (`gridKey.printWidth` / `gridKey.printHeight`).

**`-UITestHomeActions`** opens Home's row of three alone:
`home.action.{supplies,join,account}`, `home.signedIn` (the signed-in
line, plain text), and harness-only `harness.opened` (value `join` /
`account`), `harness.store`, `harness.toggleSignIn`.

Logic is tested through plain types pulled out of the views for this:
`GameProgress` (tracker: bases, outs, score, runner events, undo),
`PlayDraft` (result sheet's bases diamond), `StatsEventFilter` (stats
filters), `RunnerEventStore.savePaths/deletePaths/savedData` (where runner
records are written).

## What's covered

### Phase 3 runners (2026-10-31) - rules list approved by the user

| Rule | Unit | UI |
|---|---|---|
| 1 steal 2nd moves only the runner | `GameProgressTests.testStealSecondMovesRunnerOnly` | `testStealSecond` |
| 2 steal needs the next base empty; lead runner first | `testStealNeedsTheNextBaseEmpty` | `testStealIntoOccupiedBaseIsDisabled` |
| 3 steal of home scores for the batting team | `testStealHomeScoresForTheBattingTeam` | `testStealHomeScoresForBattingTeam` |
| 4 the saved steal record | `testStealRecordFields`, `RunnerStatsTests.testSavedDataRoundTrips` | - |
| 5 caught stealing | `testCaughtStealing` | - |
| 6 picked off | `testPickedOff` | `testPickedOff` |
| 7 third out clears the bases | `testThirdOutOnCaughtStealingClearsTheBases`, `testThirdOutOnPickoffClearsTheBases` | `testCaughtStealingThirdOutClearsTheBases` |
| 8 advance moves like a steal, no SB | `testAdvanceMovesLikeASteal`, `RunnerStatsTests.testRunningCounts` | - |
| 9 pinch runner | `testPinchRunner`, `testPinchRunnerWithoutSubstituteIsRefused` | `testPinchRunner` |
| 10 wild pitch / passed ball moves runners, scores | `testWildPitchAdvancesRunnersAndScores`, `testPassedBallAdvanceIsTaggedPB`, `PlayDraftTests.testWildPitchPlayMovesRunnersNotBatter` | `WildPitchUITests.testWildPitchScoresRunnerFromThird` |
| 11 WP with nobody moved saves no play | `PlayDraftTests.testWildPitchWithNoMovesSavesNoPlay` | - |
| 12 WP on strike three keeps the batter's out | `testWildPitchOnStrikeThreeStillCountsTheStrikeout`, `testWildPitchStrikeoutWithRunnerOutIsTwoOuts` | - |
| 13 ball four on a WP keeps the further base | `testBallFourOnWildPitchKeepsTheFurtherBase` | - |
| 14 ball four forces an unmoved runner | `testBallFourForcesAnUnmovedRunner` | - |
| 15 save blocked: backward / shared base / pass | `PlayDraftTests.testConflictsBlockSave`, `testConflictWithBatterPlaced` | - |
| 16 turning WP off resets runners | `PlayDraftTests.testTurningWildPitchOffResetsRunners` | - |
| 17 undo a steal | `testUndoSteal` | `testUndoAfterSteal` |
| 18 undo a steal of home removes the run | `testUndoStealOfHomeRemovesTheRun` | - |
| 19 undo a third-out caught stealing after the reset | `testUndoThirdOutCaughtStealingAfterReset` | - |
| 20 a later pitch is what undo removes | `testUndoTargetsTheNewerOfStealAndPitch`, `testUndoPlainPitchAfterStealKeepsTheSteal` | - |
| 21 SB / CS / PO counts | `RunnerStatsTests.testRunningCounts` | - |
| 22 stats filters apply to running | `testFiltersApplyToRunnerEvents`, `testPitchesAndRunningShareTheFilter` | - |
| 23 unlinked runner: no player copy | `testSavePathsOffline`, `testSavePathsLive`, `testDeletePaths` | - |
| Rules: runnerEvents in live room, owner game, hitter record + pitchEvents regression | - | `rules-tests/tests/runnerEvents.test.mjs` (19 cases) |

### Batch 1 - count, outs from outcomes, undo (2026-10-31)

| Rule | Tests |
|---|---|
| 1-9 how a pitch changes the count (ball, ball four, strikes, strike three, fouls, recorded results, conflicting signals, nothing marked, replay) | `CountRulesTests` |
| 10 a saved pitch's stored count and label | `SavedCountTests` |
| 11-12 outs from K / ꓘ / Out (also on older pitches with no stored count), none from anything else, third-out reset | `UndoAndOutsTests` |
| 13-16 undo restores the previous pitch's count (3-2 after an undone walk, 0-0 with nothing left), takes the out back, restores 2 outs after a third-out reset | `UndoAndOutsTests` |
| 17 a batter's next pitch starts from their own last pitch | `CountDraftTests.testSeed*`, `testBatterKey` |
| 18-20 the result sheet's derived count, hand correction, no stale publish on close | `CountDraftTests` |

The sheet's count now lives in `CountDraft`; undo's count restore and the
batter key in `GameProgress`.

**Mutation-checked:** ball four not a walk, two-strike foul adding a
strike, HBP flag ignored, terminal pitch keeping its count, sheet
publishing while closed, hand correction ignored, undo always 0-0, K not
an out (caught only after adding the older-pitch test), seed preferring
the live count over the batter's own.

The Hits/Walks row was removed from the progress panel (user, 2026-10-31).
The counters still update and sync for older builds, but nothing shows
them, so they aren't tested.

### Batch 2 - live progress sync (2026-10-31)

All in `LiveProgressSyncTests`, against `LiveProgressSync` (the tracker's
sync state now lives in `ui.progressSync`; its old property names forward
to it).

| Rule | Tests |
|---|---|
| 1 only a higher server revision applies; local changes never raise it | `testOnlyAHigherRevisionApplies`, `testLocalChangesNeverRaiseTheRevision` |
| 2-3 an unsent local change blocks room updates, for at most 5 s | `testUnsentLocalChangeBlocksEvenHigherRevisions`, `testProtectionExpiresAfterFiveSeconds` |
| 4 successful publish raises the floor (own room only); failure leaves it | `testSuccessfulPublish...`, `testFailedPublishLeavesTheFloor`, `testPublishToAnOldRoom...`, `testNoRoomMeansNothingPending` |
| 5 several changes, one publish; a change during a publish stays protected | `testSeveralChangesOnePublishClearsTheGuardOnce`, `testChangeDuringAPublishStaysProtected` |
| 6 old-build rooms compare times | `testOldBuildRoomFallsBackToTimestamps` |
| 7 a different room starts at 0; leaving resets | `testDifferentRoomStartsAtZero`, `testLeavingTheRoomResetsTheFloor` |
| 8 relaunch restores board, outs, runners - never the revision | `testSnapshotRestoresEverythingButTheRevision`, `testOlderSnapshotWithoutOutsOrRunnersKeepsCurrent` |
| 9 a game reload doesn't overwrite a newer local change | `testReloadDoesNotOverwriteANewerLocalChange`, `testReloadThatIsNewerStands`, `testFirstLookAtAGameAdoptsItsTime` |
| 10-11 an applied update replaces everything; a missing runners field keeps ours | `testAppliedUpdateReplacesEverything`, `testUpdateWithoutRunnersKeepsOurs`, `testUpdateWithEmptyRunnersClearsOurs` |

**Mutation-checked:** echo of the same revision accepted, unsent change
unprotected, protection never expiring, publish never clearing the guard,
new room keeping the old floor, a timeless snapshot treated as newer,
reload always winning, runners ignored, relaunch losing outs, an old
room's publish moving the new floor.

**Manual only:** two real devices showing the same count, outs and
runners through a live session - the timing between two phones and the
real Firestore transaction can't be reproduced here.

### Batch 3 - live pitch mirroring and event copies (2026-10-31)

`LivePitchMirrorTests` and `EventCopyWriterTests`, against
`EventCopies.swift` (`LivePitchMirror` decides the owner's copies of each
room change, `EventCopyWriter` sends every copy as its own request). The
tracker's listener and CalledPitchRecord's update/overwrite/delete
helpers now only send what those return. Rules in
`rules-tests/tests/eventCopies.test.mjs`. The rules test files now run one
at a time (`--test-concurrency=1`): they share one emulator and each clears
it before every test.

| Rule | Tests |
|---|---|
| 1 only the owner's device copies | `testOnlyTheOwnerCopies` |
| 2 game always; pitcher / hitter when named | `testCopiesGoToGamePitcherAndHitter` |
| 3 edits rewrite and deletes remove every copy | `testAnEditRewritesEveryCopy`, `testADeleteRemovesEveryCopy` |
| 4 a repeated "new" isn't copied twice | `testARepeatedAddIsSkipped` |
| 5 a restart copies everything again | `testRestartCopiesEverythingAgain` |
| 6 game copy keeps the real author; career copies are written as the owner with the partner as original author | `testGameCopyKeepsTheRealAuthor`, `testCareerCopiesAreWrittenAsTheOwner` |
| 7 copies carry the owner's game id | `testCopiesAreStampedWithTheGameId` |
| 8 cards: one per id, room wins, newest first | `testCardsMergeSeedAndRoom`, `testPitchesWithoutIdsAreKept` |
| 9 a room delete leaves the seed too | `testADeletedPitchDoesNotComeBackFromTheSeed` |
| 10 one request per copy; a refusal doesn't stop the rest | `testEachCopyIsItsOwnRequestAndADenialDoesNotStopTheOthers`, `testEveryCopyIsTriedEvenWhenAllFail` |
| 11 moving a pitch removes it from the old pitcher | `EventCopyPlanTests.testMovingAPitchToAnotherPitcher` (replaced the batch 3 test in batch 5) |
| 12 pitcher record: owner / active owner / shared coach (own rows) / everyone else | rules: `pitchers/{id}/pitchEvents` (7 tests) |
| 13 hitter record: owner only, as themselves | rules: `hitters/{id}/pitchEvents` (3 tests) |

Decided by the user (2026-11-01): a claimed pitcher has one owner. The
original owner can read its record but not write it - to track that
pitcher again they reclaim it or make a copy. The rules test "original
owner of a claimed pitcher can read but no longer add, edit or delete"
holds that line.

**Mutation-checked** (14 Swift, 2 rules - all caught): partner device
copying, hitter copy dropped, delete skipping career copies, "copy each
id once" (edits frozen), restart keeping the seen-set, repeated add
copied again, backfill author not restored, career copy written as the
partner, game id not stamped, seed winning over the room, deletion not
pruned from the seed, stopping after the first denial, stale copy
deleted from the new pitcher, oldest-first cards; rules: shared coach
editing anyone's pitcher rows, anyone creating hitter rows.

**Manual only:** a partner's edit or undo during a real two-device
session reaching the owner's permanent record - needs two signed-in
devices and the real Firebase project.

### Batch 4 - the rest of the Firestore rules (2026-10-31)

`rules-tests/tests/access.test.mjs` (42 tests) covers rules 1-22 of the
approved list: accounts and deletion markers, store orders, templates,
pitchers and their invites, players/hitters, teams, members, roster, team
invites, join codes and invites, live rooms and presence, and partner
access to the owner's game. `LiveJoinCredentialTests` covers the app side
of G1.

The user asked for four gaps to be fixed ("fix all"); the tests assert the
fixed behaviour:

| Gap | Fixed rule | App change |
|---|---|---|
| G1 any device knowing a room id could become a partner | presence needs the room's owner, or an unexpired join code / invite for that room named on it; a display device needs a display invite | joins name the code or invite (`LiveJoinCredential`), remembered per room and in the joined-session bookmark so re-entering from Home still works |
| G2 anyone knowing a pitcher id could add themselves to `sharedWith` | needs `inviteToken` naming an unexpired invite for that pitcher that you redeemed | `joinPitcherByInviteToken` burns the token first, then names it |
| G3 anyone knowing a team id could join with any role | needs the team's creator, or a redeemed, unexpired invite for that team, with no role it doesn't grant | `redeemTeamInviteToken` burns then names it (`TeamMembership.inviteToken`) |
| G4 team invites never expired and were reusable | an expired invite reads as absent (except to its creator); the redeemer burns it once | readable messages for expired / used invites |

Found by the tests and fixed too: inside a room's participant lists the
owner check read the presence document instead of the room, so the owner
could never read or remove a participant. And the three
`request.query.where` list rules (not real rules syntax) on join codes and
invites are now `resource.data.ownerUid == uid()`, which makes the app's
`cleanupExpiredJoinArtifacts` query work for the first time.

**Mutation-checked** (12 rules, all caught): no credential to join, any
room's code, expired codes, pitcher self-add without an invite, an
unredeemed pitcher invite, joining a team by id, roles beyond the invite,
expired team invite readable, team invite burned twice, owner unable to
remove presence, partner changing room status, teams deletable.

**Manual only:** a partner joining by code, by invite link, and
re-entering from Home on a real device; a coach redeeming a pitcher
invite link. These need real signed-in accounts on the real project.

### Batch 5 - editing and reviewing saved pitches (2026-11-01)

`PitchEventEditTests` (14) and `EventCopyPlanTests` (7) cover rules 1-11 of
the approved list; six tests in `rules-tests/tests/eventCopies.test.mjs`
("career rows changed after the game") cover rules 12-14. The edit logic
moved out of `CalledPitchRecord` into `PitchEventEdit` (shared with
Display), and every change to a saved pitch now goes through
`EventCopyTargets` / `EventCopyPlan` in `EventCopies.swift`.

Bugs found and fixed:

- **An edit dropped fields.** `saveEditedEvent` rebuilt the pitch field by
  field and lost the tracking mode (a scout pitch became a coach pitch),
  the catcher's estimate, the hitter link, the author, the count and the
  markers. `PitchEventEdit.applying` starts from the saved pitch and takes
  only what the sheet answers.
- **The edit sheet counted from the wrong pitch.** It seeded from the
  batter's latest pitch, so editing that pitch counted it twice and editing
  an older one started from a later count. It now starts from the pitch
  before (`countBefore`), and only an edit of the game's latest pitch moves
  the tracker's count.
- **Changes after the game never reached the career records.** Edits,
  deletes, pitcher moves and batter changes only wrote the game and live
  copies; the pitcher's and hitter's records (which career stats read)
  heard about them only through a live room. A pitch moved to another
  pitcher with no room open vanished from both. Undo deleted the pitcher's
  row but not the hitter's.
- **The review step wrote the count label by hand**, so every walk or
  strikeout saved through it showed "0-0" instead of "Ball 4" /
  "Strikeout". It now goes through `applyCount`.

Rule 3 (user's choice): only the edited pitch's count is recalculated;
later pitches keep their stored labels.

**Mutation-checked** (22 Swift + 2 rules, all caught): edit resets
tracking mode / takes hitter link / drops catcher's estimate / takes author
/ drops markers / drops count; edit seed includes the edited pitch, ignores
the lineup slot (missed at first - jersey stood in; added
`testTheBatterIsTheLineupSlotNotTheJersey`), uses the batter's latest
pitch; every edit moves the tracker count; review count written by hand;
scout in-play default gone; edit seed ignored by the sheet; no career
copies without a live room; career copy keeps the partner as author;
delete skips the hitter; moved pitch never reaches the new pitcher / stays
with the old one; hitter row or link survives a batter change; same
pitcher treated as a move; new pitcher's row keeps the hitter link.
Rules: a shared coach replacing anyone's row; anyone changing hitter rows.

**Manual only:** a partner editing a pitch during a live game and the edit
reaching the owner's record (two devices).

### Batch 6 - stats math (2026-11-01)

`StatsTests.swift` (24 tests: `PitchResultTypeTests`, `PitcherStatsTests`,
`HittingStatLineTests`, `StatsScopeTests`) covers rules 1-17 of the approved
list. The user chose: pitcher strikeouts and walks count the way the
hitter's line does, and percentages round to the nearest whole number.

Changed:

- **At-bat ends are one rule** (`AtBatCountRules.endOfAtBat`, read as
  `PitchEvent.atBatEnd`). The pitcher screen counted a strikeout or walk only
  when it carried a K/ꓘ/Walk label; the hitter's line also counted a
  third strike / fourth ball stored at 0-0. They now agree
  (`PitchStatsCalculator.isStrikeout/isWalk`). "BB" now ends an at-bat as a
  walk in the count rule too.
- **Hit by pitch is a ball** for strike %, even with "Hit By Pitch" text.
- **First-pitch strike** starts a new plate appearance when the game
  changes, the batter changes, or the previous pitch ended an at-bat -
  it used to merge the same jersey across games or after a walk.
- **Percentages round** (`statPercent`): the stats screens truncated (2 of
  3 = 66%) while the in-game summary rounded.
- **Heatmap** compares pitch names trimmed (`HeatmapSelection`); a
  "Fastball " pitch used to drop out of its own map.
- `gameCountsInStats` is now `Game.countsInStats` (testable).

Not covered: the pitcher screen shows the server's cached totals
(`PitcherStatsDoc`, Cloud Functions) until its events load - those may
still follow the old walk/strikeout rule (batch 10). `isSuccessful` and
`summarize` in `Pitch%.swift` are unused and untested.

**Mutation-checked** (20, all caught): HBP not a ball, swinging strike
not forced, location read before the ball mark, percentages cut off,
looking K needing its label, walks needing their label, "BB" not a walk,
first-pitch strike ignoring the game / the at-bat end / counting every
pitch, ROE as a hit, a walk as an at-bat, ROE as on base, slugging with
unspecified hits, a stored 0-0 strike not a K, the Hit tag ignored,
archived games always counting, untrimmed heatmap names, heatmap legacy
labels, hit spot ignoring strike/ball.

### Batch 7 - Link Profiles, Merge Duplicates, player archive (2026-11-01)

`ProfileMergeTests.swift` (30 tests: `PlayerProfileTests`,
`CombinePlanTests`, `ProfileMergeRowTests`, `ProfileMergeCleanupTests`,
`ProfileArchiveTests`) covers rules 1-16; `access.test.mjs` "merge cleanup
(batch 7 rule 17)" covers the deletes on the emulator (3 tests). The merge
decisions moved into `ProfileMerge` (ProfileMerge.swift); the Firestore
code carries them out. The user chose: Merge Duplicates is locked for
players on the open game's teams, like archiving (Link is locked too when
it combines profiles, since that can remove a row).

Fixed:

- **One unreadable roster deleted records.** Cleanup only bailed when no
  roster could be read; a single failed team read looked empty, so a
  `Player` doc only that team linked could be deleted. Now any failed read
  means nothing is deleted (`loadTeamPlayersResult`).
- **A pinch runner's record looked empty.** History checked pitches only;
  now runner events count (`ProfileMerge.historyPaths`).
- **Linked histories could be cut off.** Per-row cleanup could delete the
  duplicate `Player` doc before its `linkedPitcherIds`/`linkedHitterIds`
  reached the kept player; now they move first, or the doc stays.
- The kept player's *linked* records are never cleanup candidates (only
  its primary ones were excluded).

Not covered: the Firestore wiring itself (that `cleanupOrphanedPlayerIdentity`
and `foldProfiles` call the plan, and a failed link move keeps the doc) and
the lock dialogs on screen. Manual: a real merge on the user's data, then
checking each kid's stats still add up.

**Mutation-checked** (26, all caught): merge keeping the shared-team row,
link removing rows, a moved row not covering its team, a record with
history repointed, the row keeping its own name, checking the kept record,
a kept record left for cleanup, folded records ignoring the kept player's
links, a failed history check as no history, runner events ignored, a
failed roster read skipped, no rows still deleting, kept links deletable,
row references ignored, links not moved, a new row without the identity,
the lock inverted, keeping the newest, a locked profile not kept, two
locked allowed, linked ids not grouped, a bare Player shown, age as the
newest piece, a Pitcher's name always added; rules: a member removing a
roster row, anyone deleting a player record.

### 2026-11-02 - Home names, tracker requests

- `ProfileMergeTests.swift` `PlayerNameTests` (5): Home shows the oldest
  roster row's name, never a leftover record's; a rename reaches every
  linked record. Mutation-checked (pitcher name first, rename skipping
  linked records).
- `TrackerPolishTests.swift` (8): per-game, per-side memory of pitcher and
  batter; 7-character team names for the At Bat header; Moment share
  file names and which files exist. Mutation-checked (one pitcher shared
  by both sides).
- Layout requests (key menu mode switch, pitcher row, Pitching chips, gear
  sheet columns, Home card tints, count row) are visual - checked by
  screenshot in the demo game only; review on device.

### 2026-11-03 - fielding stats by position (rules list approved)

All in `FieldingTests.swift` (`FieldingCreditTests`, `FieldingSavedPitchTests`)
against `FieldingPlay` / `FieldingLedger`, plus `FieldingUITests`.

| Rule | Tests |
|---|---|
| 1 one-fielder out = PO only | `testOneFielderOutIsAPutoutOnly` |
| 2 last fielder PO, the rest A | `testLastFielderGetsThePutoutTheRestAssists` |
| 3 rundown: one assist each | `testRundownGivesOneAssistEach` |
| 4 double play credits + DP for those in on it | `testDoublePlayCreditsAndCountsForEveryone`, `testSingleOutIsNotADoublePlay` |
| 5 strikeout = catcher PO; no catcher, nobody | `testStrikeoutIsTheCatchersPutout`, `testStrikeoutWithNoCatcherCreditsNobody`, `testStrikeoutBatterIsNeverAskedAbout` |
| 6 error charged to the position | `testErrorIsChargedToThePosition`, `testErrorsWithoutAnErrorOnThePlayAreDropped` |
| 7 credit follows the pitch's own defense copy | `testCreditFollowsThePitchsDefenseNotTodays`, `testDefenseCopyIsTheFieldingTeamsPositions` |
| 8 unheld position counts for the team only | `testUnheldPositionCountsForTheTeamOnly`, `testTeamEventsAreItsOwnFieldingPitches` |
| 9 TC and FPCT | `testChancesAndFieldingPercent` |
| 10 innings in thirds | `testInningsAreOutsWhileThereInThirds` |
| 11 no defense copy, no stats | `testPitchesWithoutADefenseCopyAddNothing` |
| 12 stats filters apply | `testStatsFiltersApplyToFielding`, `testLinkedRecordsReadAsOnePlayer` |
| 13 edit keeps / changes / clears fielders; review keeps them | `testEditKeepsFieldersAndDefenseItDoesNotChange`, `testEditCanChangeOrClearTheFielders`, `testEditToANonOutDropsTheOuts`, `testReviewStepKeepsFieldingAndDefense` |
| 14 Firestore round trip, old docs load | `testFieldingSurvivesFirestore`, `testOlderDocumentsWithoutFieldingStillLoad` |
| 15 UI: a 6-3 entered on the sheet is saved | `FieldingUITests.testGroundoutSixThreeIsSavedWithThePitch` |

Rule 15 deviates from the approved wording: the demo game has no roster,
positions or Firestore, so the Fielding section can't open there. The UI
test checks the sheet reads 6-3 and the saved pitch's card shows "6-3";
the section's numbers from a saved pitch are the unit tests above.

**Mutation-checked:** rundown assists not de-duplicated, putout fielder
also given an assist, DP on a single out, no strikeout putout, pitches
without a defense copy counted, edit dropping saved fielders, review
dropping the defense copy, sheet saving no fielders (UI test).

Also: `BaseRunnerRulesTests` (110 checks from the phase 1-3 rules script:
credit vs base reached, forced advances, double plays, sac flies, FC,
conflicts, summaries, Codable round trips) and the Display app's
`SharedPitchModelTests` (reads pitches with and without runner data).

**Mutation-checked** (logic broken on purpose, a test failed, logic
restored): runs to the batting side, third-out undo memory, WP-strikeout
batter out, undo of a pitch's runs, third-out base clearing, ball-four WP
merge, undo target choice, caught-stealing out, undo of a steal's bases;
rules: author check on live create, owner-only update/delete in the game.

## Not covered by automation

Ranked audit (2026-10-31) of everything below that has no automated
tests, worst first. Work goes in batches in this order, the suite runs
after each, and each batch's rules are approved before its tests are written.

| # | Area | Why it's risky | What testing it needs |
|---|---|---|---|
| ~~1~~ | ~~Count, outs from outcomes, pitch undo~~ | **Done - batch 1** | |
| ~~2~~ | ~~Live progress sync~~ | **Done - batch 2** | |
| ~~3~~ | ~~Live pitch mirroring + event copies~~ | **Done - batch 3** | |
| ~~4~~ | ~~Firestore rules for everything else~~ | **Done - batch 4** (plus fixes G1-G4) | |
| ~~5~~ | ~~Edit/review rebuilds~~ | **Done - batch 5** | |
| ~~6~~ | ~~Stats math~~ | **Done - batch 6** | |
| ~~7~~ | ~~Merge Duplicates / Link Profiles / player archive scope~~ | **Done - batch 7** | |
| 8 | Primary-device session + live session lifetime (check queueing, claim, conflict, 4h expiry + renewal window, End Live Session) | Bounces to Home, lost primary, rooms silently stop | Move decisions into a plain type; device behavior stays manual |
| 9 | Pitch result sheet rules (`isOutcomeDisabled` matrix, Save gating, Hit/Error sync, Catcher flow, composer expand) | Wrong or blocked results; touch flows | Unit for the matrix; XCUITest for flows |
| 10 | Cloud Functions (`deleteAccount`, `stripeWebhook`, retail checkout, subscription entitlement) | Account deletion and payments | Functions emulator tests (Node) |
| 11 | Lineup, Player Directory, Team designation, Code Grid Keys / encrypted codes to Display | Wrong batter/pitcher/code shown | Mixed unit + UI |
| 12 | Moments editors/exporters (AVFoundation), Retail UI, subscriptions UI | Crashes/visual; low game impact; hard to automate | Exporter smoke tests on bundled clips; rest manual |

Known Phase 3 gaps:

- **UI flows not automated:** Caught Stealing for outs 1-2 (unit-tested),
  Advance, Remove/Clear, the SB/CS/PO tiles on the Hitting Stats screen
  (filters and counts are unit-tested; the screen itself isn't driven),
  the passed-ball sheet path (same code as wild pitch).
- **Live mirroring** (`RunnerEventStore.mirrorLiveChanges`) is only covered
  indirectly: its paths and rules are tested, the listener isn't.
- **Undo of a runner event after a relaunch or from the other device** is
  not supported by design (session-only), so there is nothing to test yet.

### Manual only (automation can't reach these)

| Check | Why it can't be automated here |
|---|---|
| Steal / pickoff recorded on a partner device reaches the owner's device and the runner's stats during a real live session | Needs two signed-in devices and the real Firebase project; the emulator tests prove the rules, not the two-device timing |
| Owner's device mirrors a partner's undo of a steal | Same - two real devices |
| Runners panel and diamond look right and feel right to tap | Visual / feel judgement |
| Performance with a long game's worth of runner events on a real phone | Real-device performance |

### 2026-11-04 - fielder's choice outs and the fielding key

| Rule | Test |
|---|---|
| 16. FC with a runner on 1st puts that runner out; Fielded by asks about "Runner from 1st" | `FieldersChoiceTests.testFieldersChoiceWithARunnerOnFirstPutsThemOut` |
| 17. FC takes the lead forced runner (bases loaded: from 3rd); nobody forced: the lead runner | `testFieldersChoiceTakesTheLeadForcedRunner` |
| 18. FC adds no second out if one is already entered | `testFieldersChoiceKeepsAnOutAlreadyEntered` |
| 19. Leaving FC sends that runner back to their forced base | `testLeavingFieldersChoiceSendsTheRunnerBack` |
| 20. Saved 6-4 FC: SS assist, 2B putout, 1 out, no DP, batter not asked | `testSixFourFieldersChoiceCredits` |
| 21. The key explains every table column | `testKeyExplainsEveryColumn` |
| 22. Demo game: runner on 1st, FC, SS then 2B reads 6-4, card shows 6-4 | `FieldingUITests.testSixFourFieldersChoiceIsSavedWithThePitch` |
| 23. Unassisted FC reads 6U, SS putout only | `testUnassistedFieldersChoice` |

Mutations (all caught): no auto out on FC; lead runner instead of lead
forced runner; a second out added; no revert on leaving FC.

### 2026-11-04 - one field on the result sheet

| Rule | Test |
|---|---|
| 24. Out, then Grounder, then a field tap: Out stays selected | `ResultFieldUITests.testOutStaysSelectedThroughGrounderAndAFieldTap` |
| 25. Out with a runner on keeps the hit-location field, runner drawn on it | `testOutWithARunnerKeepsTheField` |
| 26. With Out selected the bags aren't live (can't make the batter safe) | `testBasesDontMakeAnOutBatterSafe` |
| 27. The hit marker stays after the batter is placed | `testHitMarkerStaysWhenTheBatterIsPlaced` |
| 28. No result yet: a tap on a runner is the hit location, not a pick-up | `testTapOnARunnerBeforeAResultIsTheHitLocation` |
| 29. Refresh puts a picked-up runner down | `testRefreshPutsAPickedUpRunnerDown` |
| 30. A new hit location puts a picked-up runner down | `testNewHitLocationPutsAPickedUpRunnerDown` |
| 31. No result yet: the batter shows at home as "at bat", apart from the runner | `testBatterShowsAtBatBesideTheRunners` |
| 32. A placed batter's token is on the base they reached | `testBatterMovesToTheBaseTheyReached` |
| 33. An out batter reads "out"; the runner is still shown | `testOutBatterReadsOutAndTheRunnerStays` |
| 34. The prompt names the batter by number | `testPromptNamesTheBatter` |

Mutations (all caught): bags live while the batter is out (26); the old
swap of the field for the diamond on the bases stage (24-27).

Mutations for 28-30 (each caught by its own test): runners always
tappable; Refresh keeping the runner; a new location keeping the runner.

Mutations for 31-34 (each caught): batter drawn only once placed; never
moved to a base; never shown out; prompt saying "the batter".

### 2026-11-05 - RBI and runs scored

`RunsBattedInTests` (unit). Both come from the play saved on each pitch
(`HittingStatLine.runsBattedIn(for:)`, `recordRunsScored`).

| Rule | Test |
|---|---|
| 35. Every run on a hit is an RBI; the batter's own on a home run | `testRunsOnAHitAreRBIs` |
| 36. Bases-loaded walk / HBP drives in one; a base open drives in none | `testBasesLoadedWalkAndHitByPitch` |
| 37. A run on a groundout, sac fly or FC is an RBI | `testRunOnAnOutIsAnRBI` |
| 38. No RBI on reached-on-error or for a run tagged E / WP / PB | `testNoRBIForErrorsWildPitchesAndPassedBalls` |
| 39. No RBI on a play with two or more outs | `testNoRBIOnADoublePlay` |
| 40. Steal of home: a run, no RBI; a pre-runner-system pitch counts only a HR | `testStealOfHomeAndOldPitches` |
| 41. The batter scores a run on their own home run | `testBatterScoresOnAHomeRun` |
| 42. A runner scoring on another batter's pitch gets the run, once per pitch | `testRunnerScoresOnAnotherBattersPitch` |
| 43. A hand-added runner's run goes to nobody | `testUnlinkedRunnerCreditsNobody` |

Mutations (each caught): double-play check removed; ROE check removed;
tagged runs counted; no batter RBI on a HR; any linked runner credited;
no per-pitch dedup; steal of home not a run.

### 2026-11-05 - team batting and the gear sheet's own selection

| Rule | Test |
|---|---|
| 44. Fielded by one team = the other team's at-bat; an opponent with no team counts for nobody | `TeamBattingTests.testTheTeamNotFieldingIsBatting` |
| 45. A pitch with no fielding team counts only for a linked roster batter | `testOldPitchCountsByItsBatter` |
| 46. Player row: own at-bats + runs scored on teammates' pitches; other teams' running left out | `testPlayerRow` |
| 47. Team row: jersey-only batters too, and every run scored on the team's pitches | `testTeamRow` |
| 48. Tapping another player in the gear sheet highlights them there; the game's batter is unchanged | `GearSheetUITests.testTappingAPlayerInTheSheetDoesntChangeTheBatter` |
| 49. The gear sheet opens on the game's batter | `testGearSheetOpensOnTheGameBatter` |

Mutations (each caught): batting team swapped; old pitches always
counted; other games' running kept; no runner runs on a player row; no
runner runs on the Team row; sheet not starting on the game's batter
(49); the sheet's tap sent back to the game as before (48).

### 2026-11-05 - number-only players, games calendar, floating Save, Skip

| Rule | Test |
|---|---|
| 50. Number only saves "#12" and needs a jersey; otherwise a name is needed | `HomeAndPlayerFormTests.testNumberOnlySavedName` |
| 51. Avatar shows the whole number for number-only; names keep initials; "#12 Smith" / "#1 A" aren't number-only | `testAvatarText` |
| 52. Calendar month layout, games by day, opens on this month or the latest with a game | `testCalendarMonthAndGames` |
| 53. The Safe/Out + Save row sticks to the top: scrolled to the field, Out and Save are tappable and above the field (revised same day) | `ResultSheetButtonsUITests.testSaveRowSticksAboveTheField` |
| 54. The catcher's pop-up says Skip, not No | `testCatcherPopUpSaysSkip` |

Mutations (each caught): number only without a jersey; no number in the
avatar; spaces allowed in a number-only name (needed the "#1 A" case);
no blank days before the 1st; always opening on the latest game's month
(needed the later-this-month case); games keyed by time not day; Save
Result not floating; "No" back.

Not automated (needs a signed-in account): the Home calendar button and
the add/edit player forms - phone check.

Rule 53 was rewritten after the user saw the floating version sit under
the field: the row now sticks (`StickyActionBar`). Mutation: pin offset
always 0 - caught.

### 2026-11-05 - Home Add Player form

| Rule | Test |
|---|---|
| 55. Starts on the first team in list order; no teams, No team | `HomeAddPlayerTests.testDefaultTeam` |
| 56. Number only needs a team; with No team a name is required | `testNumberOnlyNeedsATeam` |

Mutations (each caught): teams in given order; number only without a team.
Opening the form needs sign-in - phone check.

### 2026-11-05 - the pitch card's result box says each thing once

`CardLinesTests` (unit): `outcomeSummaryLines` / `BaseRunnerRules.cardSummary`.

| Rule | Test |
|---|---|
| 57. A double to 2nd with Line + Hit, Deep Right is "2B" / "Line · Deep Right"; a 1B + E isn't followed by "1B" | `testScreenshotDoubleIsTwoLines` |
| 58. "Safe at" only when the credit doesn't say the base; runs and runner outs follow | `testCardSummary` |
| 59. An out with a runner says Out once and keeps 6-3; an FC (stored "Out") says FC, not Out | `testOutWithRunnerSaysOutOnce` |
| 60. A pitch with no play keeps its outcome | `testOldPitchKeepsItsOutcome` |

Mutations (each caught): outcome repeated under the play line (needed the
1B + E case - "2B" deduped on its own); "Hit" kept in the descriptor;
"Safe at" always; Out repeated (needed the FC case); no outcome for an
old pitch; solo homer counted as "1 run".

### 2026-11-05 - the review's Save opens where Save Result was

| Rule | Test |
|---|---|
| 61. The row is centred on Save Result's height, Save on its x (measured from the sheet's edges) | `ReviewSaveLayoutTests.testRowAndSaveSitOnTheAnchor` |
| 62. Never above the sheet's top or within `bottomRoom` of its bottom; Save clear of Back and the edge | `testRowAndSaveStayInsideTheSheet` |
| 63. Title and count above the row only if they fit; never the count without the title | `testOnlyWhatFitsGoesAbove` |
| 64. Demo game: unscrolled and pinned, the review's Save opens on Save Result's spot and saves | `ReviewSaveSpotUITests` (UI) |

Mutations: sheet top ignored, no bottom clamp, no x clamp, header always
above, anchor not passed (UI) - each caught. "Count needs the header"
was a redundant clause (the count's room includes the header's), so it
was removed rather than tested.

### 2026-11-06 - Scan Opponent Lineup (rules list approved)

`LineupScanTests` (unit) against `LineupScan.swift`; `LineupScanReaderTests`
runs the real on-device reader (Vision) on a drawn screenshot; access rules
in `rules-tests/tests/opponentAccess.test.mjs` (31 cases).

| Rule | Test |
|---|---|
| R1 rows by height, top to bottom, words left to right | `testRowsTopToBottomWordsLeftToRight` |
| R2 `#` = jersey; two plain numbers = order, jersey; one = order only when rows count 1, 2, 3 | `testJerseyVersusBattingOrder` |
| R3 positions and L/R thrown away, never part of a name (initials kept) | `testPositionsAndSidesAreDropped`, `testInitialsAreNotPositions` |
| R4 header words ignored | `testHeaderWordsIgnored` |
| R5 no jersey and no name dropped; a jersey alone saves "#12" | `testNumberOnlyAndEmptyRows` |
| R6 Check this: unsure read or repeated jersey | `testCheckThis` |
| R7 screenshots merge in pick order; overlap drops; same order, different player keeps both, flagged | `testMergeScreenshots` |
| M1 same jersey, names agree | `testJerseyAndNameMatch` |
| M2 same jersey, different name: flagged, one-tap match offered | `testJerseyMatchNameDiffers` |
| M3 one name match (flagged if the jersey differs) | `testNameOnlyMatch` |
| M4 never guesses between two | `testTwoCandidatesNoGuess`, `testNewPlayer` |
| M5 each roster player once (jersey beats name); removed players never | `testEachPlayerOnceAndNoArchived`, `testUnsureReadStaysFlagged` |
| A1-A2 matched reuse, new get rows; lineup only adds, no duplicates | `testPlan` |
| A3-A4 where it's written: no room = saved game (closing an open game first); an open room = the room, and the coach also writes the saved game (same spot ids) | `testRoute` |
| A5 room links reach the coach's phone; only the owner writes the saved game | `testLiveLineupLinks` |
| End to end: a drawn screenshot reads as order / name / jersey | `LineupScanReaderTests` |
| Access 1-8: partner claim, read, add/edit, no remove/delete/relink, not own or other teams, denied to display / id-knowers / other rooms / ended, expired or left rooms / changed opponent, coach-owned records, partner rename, room links | `opponentAccess.test.mjs` |

A3 was refined after approval: an open room takes the scan even when the
game isn't on screen (otherwise the room's older lineup comes back over the
saved game when the coach reopens it), and the coach's phone writes both.

**Mutation-checked:** 8 Swift (counting sequence always on, positions kept,
no merge dedupe, jersey ignoring the name, archived matched, already-batting
not skipped, open-and-live routed to the saved game, room link losing to
ours) and 8 rules (row edits not limited to the four fields, opponent check
dropped, room status ignored, records not tied to the room's owner, rename
of someone else's record, pitcher shared with the partner, adding a removed
row, room membership not checked) - each caught. (The first rules pass wrote
the mutated rules to `rules-tests/firestore.rules` by mistake, so nothing
failed; it was rerun against the real file.)

**Manual only:** a real screenshot from GameChanger / a team app, a photo
of another phone's screen, the document camera, and the two-phone partner
flow (partner scans, coach's phone saves; partner sees opponent names;
partner Bench / Put In Game reaching the coach's saved game).

### 2026-11-06 - Scan Opponent Lineup on real screenshots (second list, approved)

The user's GameChanger box score (`PitchMarkTests/Fixtures/LineupBoxScoreGameChanger.png`,
committed with their OK) is a test: `LineupScanReaderTests.testRealGameChangerBoxScore`
reads it with Vision and expects exactly the twelve batters, in order, with
their jerseys, and only the cut-short names flagged.

| Rule | Test |
|---|---|
| R3 "(C)" / "(1B)" always dropped; a single letter before the name is an initial | `testParenthesizedPositionsAndInitials` |
| R8 "#" split off text it's stuck to ("Hanew...#12") | `testHashSplitsOff` |
| R9 numbers right of the name are stat columns (a 0 read as "O" too); one trailing number is the jersey only without "#" | `testStatColumnsIgnored` |
| R10 "TB:" / "SB:" lines and the TEAM row dropped | `testSummaryLinesDropped` |
| R11 "..." trimmed off a cut-short name, flagged | `testTruncatedNames` |
| R12 Keep: what starts kept ("#" style, number-only, numbered names) | `testLikelyBatters` |
| R12 Keep list: ticking joins where it was read, unticking returns to "Other text found" in read order | `testReviewKeepList` |
| R6 repeated jersey flagged only among kept rows | `testRepeatedJerseyOnlyAmongKept` |

**Mutation-checked (11, each caught):** no "#" split, parenthesized
positions kept, initials dropped, stat columns read as order/jersey, colon
summary lines kept, TEAM row kept, "..." left on, "#" style ignored,
repeated jerseys counted over junk, ticked rows appended at the end, "O"
read as a name.

### 2026-11-06 - partner controls through the room (A6-A8, approved)

The partner's phone now loads the owner's game itself (`loadGameForPartner`,
once per room - several join paths never pass a game id), which is what
loads both rosters, the opponent claim and the gear sheet's teams.

| Rule | Test |
|---|---|
| A6 room positions reach everyone's game copy; the coach saves; a room with no positions never clears the game's | `LineupScanTests.testPositionsFromRoom`; rules: "a partner writes field positions into the room, not the saved game" |
| A7 the coach's phone fills in links / positions the room is missing, only then | `testCoachPublishesWhatTheRoomIsMissing` |
| A8 an empty room gets the game's lineup and its own spots' links; a room with a lineup is never overwritten | `testSeedForEmptyRoom` |

**Mutation-checked (4, each caught):** a missing room map clearing the
game's positions, publishing over the room's own map, seeding a room that
already has a lineup, copying links for spots not in the lineup. The rules
case needed no rules change (participants already update the room); it
guards the partner-can't-write-the-saved-game line.

**Manual only:** the two-phone check this was written for (parent sees the
opponent's lineup with names, gear sheet with Order / Bench / Put In Game /
positions; changes reach the coach's saved game). Xcode console lines
starting `🧾 room lineup:` show what each phone has.

### 2026-11-07 - partners read the game's own team (H1-H4, approved, deployed)

Rules in `rules-tests/tests/opponentAccess.test.mjs` ("H1-H4" block, 7 cases
plus the changed claim case): a connected parent reads the room's game's own
team (roster + team doc) through a `partnerAccess` claim; never adds, edits,
archives, deletes or renames there; same lapses as the opponent access; the
opponent's add/edit is unchanged. App: the own-team claim passes
`canEdit: false`, so it never becomes an `OpponentPartnerAccess` grant (the
grant is what turns on coach-owned records and partner renames).

**Mutation-checked (5, each caught):** own team not readable, own team
writable through create, through update, any team counted as the game's,
own-team claim refused.

Why: the parent's gear sheet showed our batters as "Not on roster" in the
opponent's column - their links pointed at a roster the parent couldn't read.
