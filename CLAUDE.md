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

There is **no test target**, and the sandbox has no tap automation (`osascript`
is blocked by TCC) and no video decoding. Practically:

- Pure logic gets verified by compiling a standalone Swift script that imports
  nothing and asserts against the rules directly. `AtBatCountRules` was validated
  this way with 27 assertions plus a full at-bat simulation before shipping.
- Anything involving touch has to be verified by the user on a device or
  simulator. Ask; don't claim it works.
- Screenshots of the running simulator do work and are worth taking for layout
  changes.

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

In `PitchResultsSheetView`, the count is *derived* (`countSeed` + current
selection) rather than stored. The `.onChange(of: resolvedCount)` publisher is
gated on `isPresented` — without that guard, `resetSelections()` during sheet
teardown publishes the stale pre-pitch seed over the count that was just saved.
That regression is subtle and reproduced as a sequence like `["1-0","0-1","1-0"]`
with the main screen stuck at `0-0`.

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

**Never put join codes or invite tokens on `/liveGames/{liveId}`.** That document
is readable by display participants and display-only sessions, which are meant to
render a called pitch and nothing else — a credential there lets a display device
rejoin as a full participant with write access to pitch events. They live in
`users/{uid}/liveSessions/{liveId}`, which is owner-only.

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
