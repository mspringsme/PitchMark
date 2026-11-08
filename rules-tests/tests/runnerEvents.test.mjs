// Firestore rules for runner events (steals, caught stealing, pickoffs,
// advances, pinch runners) - liveGames/{id}/runnerEvents,
// users/{owner}/games/{gid}/runnerEvents and hitters/{id}/runnerEvents -
// plus regression checks that the matching pitchEvents rules didn't change.
//
// Roles:
//   owner    - owns the game, the live room and the hitter record
//   partner  - joined the live room (participants/{uid})
//   display  - display-only device in the room (displayParticipants/{uid})
//   stranger - signed in, no connection to any of it

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, Timestamp, updateDoc } from "firebase/firestore";

const LIVE = "live1";
const GAME = "game1";
const HITTER = "hitter1";

let env;

const db = (uid) => env.authenticatedContext(uid).firestore();

const runnerEvent = (createdByUid, extra = {}) => ({
  id: "ev",
  timestamp: Timestamp.fromMillis(1_000),
  kind: "SB",
  from: 1,
  to: 2,
  runner: { id: "cell-1", label: "#1", hitterId: HITTER },
  basesBefore: { first: { id: "cell-1", label: "#1", hitterId: HITTER } },
  gameId: GAME,
  hitterId: HITTER,
  createdByUid,
  ...extra,
});

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
    const now = Timestamp.now();
    const later = Timestamp.fromMillis(Date.now() + 4 * 3600 * 1000);
    await setDoc(doc(fs, `liveGames/${LIVE}`), {
      ownerUid: "owner",
      status: "active",
      ownerGameId: GAME,
      createdAt: now,
      expiresAt: later,
    });
    await setDoc(doc(fs, `liveGames/${LIVE}/participants/partner`), { uid: "partner" });
    await setDoc(doc(fs, `liveGames/${LIVE}/displayParticipants/display`), { uid: "display" });
    await setDoc(doc(fs, `users/owner/games/${GAME}`), { opponent: "Demo" });
    await setDoc(doc(fs, `hitters/${HITTER}`), { ownerUid: "owner", name: "Kid" });
    // Existing events to read / update / delete.
    await setDoc(doc(fs, `liveGames/${LIVE}/runnerEvents/byOwner`), runnerEvent("owner"));
    await setDoc(doc(fs, `liveGames/${LIVE}/runnerEvents/byPartner`), runnerEvent("partner"));
    await setDoc(doc(fs, `users/owner/games/${GAME}/runnerEvents/existing`), runnerEvent("partner", { liveId: LIVE }));
    await setDoc(doc(fs, `hitters/${HITTER}/runnerEvents/existing`), runnerEvent("owner"));
    // Same shape for the pitchEvents regression checks.
    await setDoc(doc(fs, `liveGames/${LIVE}/pitchEvents/byOwner`), { createdByUid: "owner" });
    await setDoc(doc(fs, `liveGames/${LIVE}/pitchEvents/byPartner`), { createdByUid: "partner" });
    await setDoc(doc(fs, `users/owner/games/${GAME}/pitchEvents/existing`), { createdByUid: "partner" });
  });
});

describe("liveGames/{id}/runnerEvents", () => {
  const path = (id) => `liveGames/${LIVE}/runnerEvents/${id}`;

  it("owner can create, read and delete", async () => {
    await assertSucceeds(setDoc(doc(db("owner"), path("new")), runnerEvent("owner")));
    await assertSucceeds(getDoc(doc(db("owner"), path("byPartner"))));
    await assertSucceeds(deleteDoc(doc(db("owner"), path("byPartner"))));
  });

  it("partner can create under their own uid", async () => {
    await assertSucceeds(setDoc(doc(db("partner"), path("new")), runnerEvent("partner")));
  });

  it("partner cannot create under someone else's uid", async () => {
    await assertFails(setDoc(doc(db("partner"), path("new")), runnerEvent("owner")));
  });

  it("partner can delete their own event but not the owner's", async () => {
    await assertSucceeds(deleteDoc(doc(db("partner"), path("byPartner"))));
    await assertFails(deleteDoc(doc(db("partner"), path("byOwner"))));
  });

  it("display device can read but not write", async () => {
    await assertSucceeds(getDoc(doc(db("display"), path("byOwner"))));
    await assertFails(setDoc(doc(db("display"), path("new")), runnerEvent("display")));
    await assertFails(deleteDoc(doc(db("display"), path("byOwner"))));
  });

  it("stranger can neither read nor write", async () => {
    await assertFails(getDoc(doc(db("stranger"), path("byOwner"))));
    await assertFails(setDoc(doc(db("stranger"), path("new")), runnerEvent("stranger")));
  });

  it("signed-out users are denied", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, path("byOwner"))));
    await assertFails(setDoc(doc(anon, path("new")), runnerEvent("owner")));
  });
});

describe("users/{owner}/games/{gid}/runnerEvents", () => {
  const path = (id) => `users/owner/games/${GAME}/runnerEvents/${id}`;

  it("owner can create, update and delete", async () => {
    await assertSucceeds(setDoc(doc(db("owner"), path("new")), runnerEvent("owner")));
    await assertSucceeds(updateDoc(doc(db("owner"), path("existing")), { kind: "CS" }));
    await assertSucceeds(deleteDoc(doc(db("owner"), path("existing"))));
  });

  it("active partner can create with the room's liveId", async () => {
    await assertSucceeds(setDoc(doc(db("partner"), path("new")), runnerEvent("partner", { liveId: LIVE })));
  });

  it("partner cannot create without a liveId (no join code on the game)", async () => {
    await assertFails(setDoc(doc(db("partner"), path("new")), runnerEvent("partner")));
  });

  it("partner cannot create under someone else's uid", async () => {
    await assertFails(setDoc(doc(db("partner"), path("new")), runnerEvent("owner", { liveId: LIVE })));
  });

  it("partner cannot update or delete", async () => {
    await assertFails(updateDoc(doc(db("partner"), path("existing")), { kind: "CS" }));
    await assertFails(deleteDoc(doc(db("partner"), path("existing"))));
  });

  it("stranger cannot create, even naming the room", async () => {
    await assertFails(setDoc(doc(db("stranger"), path("new")), runnerEvent("stranger", { liveId: LIVE })));
    await assertFails(getDoc(doc(db("stranger"), path("existing"))));
  });

  it("partner of an ended room cannot create", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), `liveGames/${LIVE}`), { status: "ended" });
    });
    await assertFails(setDoc(doc(db("partner"), path("new")), runnerEvent("partner", { liveId: LIVE })));
  });
});

describe("hitters/{id}/runnerEvents", () => {
  const path = (id) => `hitters/${HITTER}/runnerEvents/${id}`;

  it("hitter owner can create as themselves, read and delete", async () => {
    await assertSucceeds(setDoc(doc(db("owner"), path("new")), runnerEvent("owner")));
    await assertSucceeds(getDoc(doc(db("owner"), path("existing"))));
    await assertSucceeds(deleteDoc(doc(db("owner"), path("existing"))));
  });

  it("hitter owner cannot write a record authored by someone else", async () => {
    await assertFails(setDoc(doc(db("owner"), path("new")), runnerEvent("partner")));
  });

  it("partner and stranger are denied", async () => {
    await assertFails(setDoc(doc(db("partner"), path("new")), runnerEvent("partner")));
    await assertFails(getDoc(doc(db("partner"), path("existing"))));
    await assertFails(setDoc(doc(db("stranger"), path("new")), runnerEvent("stranger")));
    await assertFails(getDoc(doc(db("stranger"), path("existing"))));
  });
});

describe("pitchEvents rules unchanged (regression)", () => {
  it("live room: partner creates own, deletes own, not the owner's; stranger denied", async () => {
    const path = (id) => `liveGames/${LIVE}/pitchEvents/${id}`;
    await assertSucceeds(setDoc(doc(db("partner"), path("new")), { createdByUid: "partner" }));
    await assertFails(setDoc(doc(db("partner"), path("new2")), { createdByUid: "owner" }));
    await assertSucceeds(deleteDoc(doc(db("partner"), path("byPartner"))));
    await assertFails(deleteDoc(doc(db("partner"), path("byOwner"))));
    await assertSucceeds(getDoc(doc(db("display"), path("byOwner"))));
    await assertFails(getDoc(doc(db("stranger"), path("byOwner"))));
  });

  it("owner game: partner creates with liveId only; cannot update or delete", async () => {
    const path = (id) => `users/owner/games/${GAME}/pitchEvents/${id}`;
    await assertSucceeds(setDoc(doc(db("partner"), path("new")), { createdByUid: "partner", liveId: LIVE }));
    await assertFails(setDoc(doc(db("partner"), path("new2")), { createdByUid: "partner" }));
    await assertFails(updateDoc(doc(db("partner"), path("existing")), { outcome: "Out" }));
    await assertFails(deleteDoc(doc(db("partner"), path("existing"))));
    await assertSucceeds(deleteDoc(doc(db("owner"), path("existing"))));
  });
});
