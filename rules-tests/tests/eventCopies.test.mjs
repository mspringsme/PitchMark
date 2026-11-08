// Firestore rules for the career copies of a pitch the owner's device
// mirrors out of a live room (batch 3, approved 2026-10-31):
//   pitchers/{pid}/pitchEvents and hitters/{hid}/pitchEvents
//
// Roles:
//   owner    - created the pitcher / hitter (ownerUid)
//   claimer  - claimed the pitcher (claimedByUid): the active owner
//   coach    - the pitcher is shared with them (sharedWith)
//   stranger - signed in, no connection

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, deleteField, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";

const PITCHER = "pitcher1";
const CLAIMED = "pitcher2";
const HITTER = "hitter1";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const pitch = (createdByUid, extra = {}) => ({ createdByUid, outcome: "1B", gameId: "game1", ...extra });

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-pitchmark-rules",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8085,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, `pitchers/${PITCHER}`), { ownerUid: "owner", sharedWith: ["coach"], name: "Ace" });
    await setDoc(doc(fs, `pitchers/${CLAIMED}`), { ownerUid: "owner", claimedByUid: "claimer", sharedWith: [], name: "Kid" });
    await setDoc(doc(fs, `hitters/${HITTER}`), { ownerUid: "owner", name: "Kid" });
    await setDoc(doc(fs, `pitchers/${PITCHER}/pitchEvents/byOwner`), pitch("owner"));
    await setDoc(doc(fs, `pitchers/${PITCHER}/pitchEvents/byCoach`), pitch("coach"));
    await setDoc(doc(fs, `pitchers/${CLAIMED}/pitchEvents/existing`), pitch("owner"));
    await setDoc(doc(fs, `hitters/${HITTER}/pitchEvents/existing`), pitch("owner"));
  });
});

describe("pitchers/{id}/pitchEvents", () => {
  const path = (id) => `pitchers/${PITCHER}/pitchEvents/${id}`;
  const claimed = (id) => `pitchers/${CLAIMED}/pitchEvents/${id}`;

  it("owner can read, add as themselves (keeping the partner as original author), edit and delete", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), path("byCoach"))));
    await assertSucceeds(setDoc(doc(db("owner"), path("new")),
      pitch("owner", { originalCreatedByUid: "partner" })));
    await assertSucceeds(updateDoc(doc(db("owner"), path("byCoach")), { outcome: "2B" }));
    await assertSucceeds(deleteDoc(doc(db("owner"), path("byCoach"))));
  });

  it("nobody can add a row authored by someone else", async () => {
    await assertFails(setDoc(doc(db("owner"), path("new")), pitch("partner")));
    await assertFails(setDoc(doc(db("coach"), path("new")), pitch("owner")));
  });

  it("active owner of a claimed pitcher can read, add, edit and delete", async () => {
    await assertSucceeds(getDoc(doc(db("claimer"), claimed("existing"))));
    await assertSucceeds(setDoc(doc(db("claimer"), claimed("new")), pitch("claimer")));
    await assertSucceeds(updateDoc(doc(db("claimer"), claimed("existing")), { outcome: "2B" }));
    await assertSucceeds(deleteDoc(doc(db("claimer"), claimed("existing"))));
  });

  it("original owner of a claimed pitcher can read but no longer add, edit or delete", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), claimed("existing"))));
    await assertFails(setDoc(doc(db("owner"), claimed("new")), pitch("owner")));
    await assertFails(updateDoc(doc(db("owner"), claimed("existing")), { outcome: "2B" }));
    await assertFails(deleteDoc(doc(db("owner"), claimed("existing"))));
  });

  it("shared coach can read and add rows they wrote", async () => {
    await assertSucceeds(getDoc(doc(db("coach"), path("byOwner"))));
    await assertSucceeds(setDoc(doc(db("coach"), path("new")), pitch("coach")));
  });

  it("shared coach can edit and delete only their own rows", async () => {
    await assertSucceeds(updateDoc(doc(db("coach"), path("byCoach")), { outcome: "2B" }));
    await assertFails(updateDoc(doc(db("coach"), path("byOwner")), { outcome: "2B" }));
    await assertFails(deleteDoc(doc(db("coach"), path("byOwner"))));
    await assertSucceeds(deleteDoc(doc(db("coach"), path("byCoach"))));
  });

  it("stranger and signed-out users are denied", async () => {
    await assertFails(getDoc(doc(db("stranger"), path("byOwner"))));
    await assertFails(setDoc(doc(db("stranger"), path("new")), pitch("stranger")));
    await assertFails(updateDoc(doc(db("stranger"), path("byOwner")), { outcome: "2B" }));
    await assertFails(deleteDoc(doc(db("stranger"), path("byOwner"))));
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, path("byOwner"))));
    await assertFails(setDoc(doc(anon, path("new")), pitch("owner")));
  });
});

describe("hitters/{id}/pitchEvents", () => {
  const path = (id) => `hitters/${HITTER}/pitchEvents/${id}`;

  it("hitter owner can read, add as themselves, edit and delete", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), path("existing"))));
    await assertSucceeds(setDoc(doc(db("owner"), path("new")),
      pitch("owner", { originalCreatedByUid: "partner" })));
    await assertSucceeds(updateDoc(doc(db("owner"), path("existing")), { outcome: "2B" }));
    await assertSucceeds(deleteDoc(doc(db("owner"), path("existing"))));
  });

  it("hitter owner cannot add a row authored by someone else", async () => {
    await assertFails(setDoc(doc(db("owner"), path("new")), pitch("partner")));
  });

  it("everyone else is denied, including a live partner and a pitcher's coach", async () => {
    for (const who of ["partner", "coach", "stranger"]) {
      await assertFails(getDoc(doc(db(who), path("existing"))));
      await assertFails(setDoc(doc(db(who), path("new")), pitch(who)));
      await assertFails(updateDoc(doc(db(who), path("existing")), { outcome: "2B" }));
      await assertFails(deleteDoc(doc(db(who), path("existing"))));
    }
  });
});

// Batch 5 (approved 2026-11-01): a pitch edited, moved or unlinked after the
// game writes the career rows directly - an edit replaces the row (setDoc
// over an existing document is an update to the rules).
describe("career rows changed after the game", () => {
  const pitcherRow = (id) => `pitchers/${PITCHER}/pitchEvents/${id}`;
  const hitterRow = (id) => `hitters/${HITTER}/pitchEvents/${id}`;

  it("rule 12: the pitcher's owner can replace a row with the edited pitch", async () => {
    await assertSucceeds(setDoc(doc(db("owner"), pitcherRow("byCoach")),
      pitch("owner", { originalCreatedByUid: "coach", outcome: "2B" })));
    await assertSucceeds(setDoc(doc(db("owner"), pitcherRow("byOwner")), pitch("owner", { outcome: "HR" })));
  });

  it("rule 12: a shared coach can replace their own row but not anyone else's", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), pitcherRow("byCoach")), pitch("coach", { outcome: "2B" })));
    await assertFails(setDoc(doc(db("coach"), pitcherRow("byOwner")), pitch("coach", { outcome: "2B" })));
  });

  it("rule 12: unlinking the batter clears the roster fields on the row", async () => {
    await assertSucceeds(updateDoc(doc(db("owner"), pitcherRow("byOwner")),
      { opponentJersey: "12", opponentBatterId: deleteField(), hitterId: deleteField() }));
    await assertSucceeds(updateDoc(doc(db("coach"), pitcherRow("byCoach")),
      { opponentJersey: "12", hitterId: deleteField() }));
  });

  it("rule 12: moving a pitch deletes the old pitcher's row and adds it to the new one's", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "pitchers/pitcher3"), { ownerUid: "owner", sharedWith: ["coach"], name: "Two" });
    });
    await assertSucceeds(deleteDoc(doc(db("owner"), pitcherRow("byOwner"))));
    await assertSucceeds(setDoc(doc(db("owner"), "pitchers/pitcher3/pitchEvents/byOwner"),
      pitch("owner", { pitcherId: "pitcher3" })));
    await assertSucceeds(setDoc(doc(db("coach"), "pitchers/pitcher3/pitchEvents/byCoach"),
      pitch("coach", { pitcherId: "pitcher3" })));
  });

  it("rule 13: anyone the pitcher isn't shared with can't replace, unlink or delete a row", async () => {
    for (const who of ["stranger", "partner"]) {
      await assertFails(setDoc(doc(db(who), pitcherRow("byOwner")), pitch(who)));
      await assertFails(updateDoc(doc(db(who), pitcherRow("byOwner")), { hitterId: deleteField() }));
      await assertFails(deleteDoc(doc(db(who), pitcherRow("byOwner"))));
    }
  });

  it("rule 14: the hitter's owner can replace or delete a row; nobody else can", async () => {
    await assertSucceeds(setDoc(doc(db("owner"), hitterRow("existing")),
      pitch("owner", { originalCreatedByUid: "partner", outcome: "2B" })));
    for (const who of ["partner", "coach", "stranger"]) {
      await assertFails(setDoc(doc(db(who), hitterRow("existing")), pitch(who)));
      await assertFails(deleteDoc(doc(db(who), hitterRow("existing"))));
    }
    await assertSucceeds(deleteDoc(doc(db("owner"), hitterRow("existing"))));
  });
});
