// Team schedule (approved 2026-11-22): team members, invites and team
// tourneys.
//   R1 only a team's creator makes an invite (before this, anyone could
//      make one for any team and join it)
//   R2 invites are Scheduler ("assistant") or Family ("parent") only; a
//      reusable code is Family only
//   R3 a family joins with the reusable code as Family only; an expired
//      code or another team's code fails
//   R4 a reusable code can't be used up
//   R5 a Scheduler still joins once with a single-use invite
//   R6 only the creator lists the members
//   R7 the creator removes anyone; a member leaves; a member can't remove
//      someone else
//   R8 the creator and members read team tourneys; outsiders and removed
//      members can't
//   R9 the creator and Schedulers add and edit team tourneys; Families
//      can't; the team id must match; nobody deletes
//   R10 a Scheduler keeps a shared team tourney's link copy current; a
//      Family or outsider can't; the owner can't change
//
// Expected values come from the approved rules list, not from running the
// rules.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp, collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc,
} from "firebase/firestore";

const TEAM = "reds";
const OTHER = "hawks";
const SHARE = "0123456789abcdef0123456789abcdef";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const put = (path, data) => admin((f) => setDoc(doc(f, path), data));
const future = () => Timestamp.fromMillis(Date.now() + 86_400_000);
const past = () => Timestamp.fromMillis(Date.now() - 86_400_000);

const token = (extra = {}) => ({
  teamId: TEAM, roles: ["parent"], createdByUid: "coach", expiresAt: future(), ...extra,
});
const membership = (uid, roles, inviteToken) => ({
  uid, roles, addedByUid: "coach", inviteToken, name: uid,
});
const tourney = (extra = {}) => ({ name: "Summer Slam", teamId: TEAM, games: [], ...extra });

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
  await put(`teams/${TEAM}`, { createdByUid: "coach", name: "Reds" });
  await put(`teams/${OTHER}`, { createdByUid: "othercoach", name: "Hawks" });
  await put(`teams/${TEAM}/members/coach`, { uid: "coach", roles: ["coach"], addedByUid: "coach" });
  await put(`teams/${TEAM}/members/helper`, membership("helper", ["assistant"], "used1"));
  await put(`teams/${TEAM}/members/family`, membership("family", ["parent"], "fam"));
  await put("teamInviteTokens/fam", token({ multiUse: true, expiresAt: future() }));
  await put("teamInviteTokens/famOld", token({ multiUse: true, expiresAt: past() }));
  await put("teamInviteTokens/famHawks", token({ teamId: OTHER, createdByUid: "othercoach", multiUse: true }));
  await put("teamInviteTokens/sched", token({ roles: ["assistant"] }));
  await put(`teams/${TEAM}/tourneys/t1`, tourney());
});

describe("R1 only the team's creator makes an invite", () => {
  it("the creator can", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "teamInviteTokens/new"), token()));
  });

  it("someone else can't make one for the team - and so can't join it", async () => {
    await assertFails(setDoc(doc(db("stranger"), "teamInviteTokens/mint"),
      token({ createdByUid: "stranger", roles: ["assistant"] })));
    await assertFails(setDoc(doc(db("family"), "teamInviteTokens/mint2"),
      token({ createdByUid: "family", roles: ["assistant"] })), "a member can't either");
  });
});

describe("R2 invite roles", () => {
  it("Scheduler and Family invites are fine", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "teamInviteTokens/a"), token({ roles: ["assistant"] })));
    await assertSucceeds(setDoc(doc(db("coach"), "teamInviteTokens/b"), token({ roles: ["parent"], multiUse: true })));
  });

  it("no Coach invites", async () => {
    await assertFails(setDoc(doc(db("coach"), "teamInviteTokens/c"), token({ roles: ["coach"] })));
  });

  it("a reusable code is Family only", async () => {
    await assertFails(setDoc(doc(db("coach"), "teamInviteTokens/d"), token({ roles: ["assistant"], multiUse: true })));
    await assertFails(setDoc(doc(db("coach"), "teamInviteTokens/e"),
      token({ roles: ["assistant", "parent"], multiUse: true })));
  });
});

describe("R3 joining with the family code", () => {
  it("a family joins as Family", async () => {
    await assertSucceeds(setDoc(doc(db("newfam"), `teams/${TEAM}/members/newfam`),
      membership("newfam", ["parent"], "fam")));
  });

  it("not as a Scheduler or Coach", async () => {
    await assertFails(setDoc(doc(db("newfam"), `teams/${TEAM}/members/newfam`),
      membership("newfam", ["assistant"], "fam")));
    await assertFails(setDoc(doc(db("newfam"), `teams/${TEAM}/members/newfam`),
      membership("newfam", ["coach"], "fam")));
  });

  it("an expired code fails", async () => {
    await assertFails(setDoc(doc(db("newfam"), `teams/${TEAM}/members/newfam`),
      membership("newfam", ["parent"], "famOld")));
  });

  it("another team's code fails", async () => {
    await assertFails(setDoc(doc(db("newfam"), `teams/${TEAM}/members/newfam`),
      membership("newfam", ["parent"], "famHawks")));
  });

  it("no code at all fails", async () => {
    await assertFails(setDoc(doc(db("newfam"), `teams/${TEAM}/members/newfam`),
      { uid: "newfam", roles: ["parent"], addedByUid: "coach" }));
  });
});

describe("R4 the family code can't be used up", () => {
  it("nobody can burn it", async () => {
    await assertFails(updateDoc(doc(db("newfam"), "teamInviteTokens/fam"),
      { redeemedByUid: "newfam", redeemedAt: Timestamp.now() }));
  });

  it("two families both join with it", async () => {
    await assertSucceeds(setDoc(doc(db("fam1"), `teams/${TEAM}/members/fam1`), membership("fam1", ["parent"], "fam")));
    await assertSucceeds(setDoc(doc(db("fam2"), `teams/${TEAM}/members/fam2`), membership("fam2", ["parent"], "fam")));
  });
});

describe("R5 a Scheduler joins once with their invite", () => {
  it("burn, then join as Scheduler", async () => {
    await assertSucceeds(updateDoc(doc(db("newhelper"), "teamInviteTokens/sched"),
      { redeemedByUid: "newhelper", redeemedAt: Timestamp.now() }));
    await assertSucceeds(setDoc(doc(db("newhelper"), `teams/${TEAM}/members/newhelper`),
      membership("newhelper", ["assistant"], "sched")));
  });

  it("someone else can't use it after", async () => {
    await put("teamInviteTokens/sched", token({ roles: ["assistant"], redeemedByUid: "newhelper" }));
    await assertFails(updateDoc(doc(db("other"), "teamInviteTokens/sched"),
      { redeemedByUid: "other", redeemedAt: Timestamp.now() }));
    await assertFails(setDoc(doc(db("other"), `teams/${TEAM}/members/other`),
      membership("other", ["assistant"], "sched")));
  });
});

describe("R6 the members list", () => {
  it("the creator lists members", async () => {
    await assertSucceeds(getDocs(collection(db("coach"), `teams/${TEAM}/members`)));
  });

  it("members and outsiders can't", async () => {
    await assertFails(getDocs(collection(db("helper"), `teams/${TEAM}/members`)));
    await assertFails(getDocs(collection(db("family"), `teams/${TEAM}/members`)));
    await assertFails(getDocs(collection(db("stranger"), `teams/${TEAM}/members`)));
  });
});

describe("R7 removing and leaving", () => {
  it("the creator removes anyone", async () => {
    await assertSucceeds(deleteDoc(doc(db("coach"), `teams/${TEAM}/members/family`)));
    await assertSucceeds(deleteDoc(doc(db("coach"), `teams/${TEAM}/members/helper`)));
  });

  it("a member leaves", async () => {
    await assertSucceeds(deleteDoc(doc(db("family"), `teams/${TEAM}/members/family`)));
  });

  it("a member can't remove someone else", async () => {
    await assertFails(deleteDoc(doc(db("helper"), `teams/${TEAM}/members/family`)));
    await assertFails(deleteDoc(doc(db("family"), `teams/${TEAM}/members/helper`)));
  });
});

describe("R8 reading team tourneys", () => {
  it("the creator and every member read them", async () => {
    for (const uid of ["coach", "helper", "family"]) {
      await assertSucceeds(getDoc(doc(db(uid), `teams/${TEAM}/tourneys/t1`)));
      await assertSucceeds(getDocs(collection(db(uid), `teams/${TEAM}/tourneys`)));
    }
  });

  it("outsiders can't", async () => {
    await assertFails(getDoc(doc(db("stranger"), `teams/${TEAM}/tourneys/t1`)));
    await assertFails(getDocs(collection(db("stranger"), `teams/${TEAM}/tourneys`)));
  });

  it("a removed member can't any more", async () => {
    await admin((f) => deleteDoc(doc(f, `teams/${TEAM}/members/family`)));
    await assertFails(getDoc(doc(db("family"), `teams/${TEAM}/tourneys/t1`)));
  });
});

describe("R9 editing team tourneys", () => {
  it("the creator and a Scheduler add and edit", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), `teams/${TEAM}/tourneys/t2`), tourney({ name: "Fall Classic" })));
    await assertSucceeds(setDoc(doc(db("helper"), `teams/${TEAM}/tourneys/t3`), tourney({ name: "Turkey Bowl" })));
    await assertSucceeds(setDoc(doc(db("helper"), `teams/${TEAM}/tourneys/t1`), tourney({ name: "Renamed" })));
  });

  it("a Family can't", async () => {
    await assertFails(setDoc(doc(db("family"), `teams/${TEAM}/tourneys/t2`), tourney()));
    await assertFails(updateDoc(doc(db("family"), `teams/${TEAM}/tourneys/t1`), { name: "Hacked" }));
  });

  it("an outsider can't", async () => {
    await assertFails(setDoc(doc(db("stranger"), `teams/${TEAM}/tourneys/t2`), tourney()));
  });

  it("the team id must be this team", async () => {
    await assertFails(setDoc(doc(db("coach"), `teams/${TEAM}/tourneys/t2`), tourney({ teamId: OTHER })));
    await assertFails(setDoc(doc(db("coach"), `teams/${TEAM}/tourneys/t2`), { name: "No team" }));
  });

  it("nobody deletes one", async () => {
    await assertFails(deleteDoc(doc(db("coach"), `teams/${TEAM}/tourneys/t1`)));
    await assertFails(deleteDoc(doc(db("helper"), `teams/${TEAM}/tourneys/t1`)));
  });
});

describe("R10 a shared team tourney's link copy", () => {
  beforeEach(() => put(`sharedTourneys/${SHARE}`, { ownerUid: "coach", teamId: TEAM, name: "Summer Slam" }));

  it("a Scheduler keeps it current, owner unchanged", async () => {
    await assertSucceeds(setDoc(doc(db("helper"), "sharedTourneys", SHARE),
      { ownerUid: "coach", teamId: TEAM, name: "Summer Slam - new times" }));
  });

  it("a Family or outsider can't", async () => {
    await assertFails(setDoc(doc(db("family"), "sharedTourneys", SHARE),
      { ownerUid: "coach", teamId: TEAM, name: "Hacked" }));
    await assertFails(setDoc(doc(db("stranger"), "sharedTourneys", SHARE),
      { ownerUid: "coach", teamId: TEAM, name: "Hacked" }));
  });

  it("nobody changes the owner or moves it to another team", async () => {
    await assertFails(setDoc(doc(db("helper"), "sharedTourneys", SHARE),
      { ownerUid: "helper", teamId: TEAM, name: "Mine now" }));
    await assertFails(setDoc(doc(db("helper"), "sharedTourneys", SHARE),
      { ownerUid: "coach", teamId: OTHER, name: "Elsewhere" }));
  });

  it("a Scheduler can stop sharing it; a Family can't", async () => {
    await assertFails(deleteDoc(doc(db("family"), "sharedTourneys", SHARE)));
    await assertSucceeds(deleteDoc(doc(db("helper"), "sharedTourneys", SHARE)));
  });

  it("a personal copy is still owner-only", async () => {
    await put(`sharedTourneys/${"a".repeat(32)}`, { ownerUid: "coach", name: "Mine" });
    await assertFails(setDoc(doc(db("helper"), "sharedTourneys", "a".repeat(32)), { ownerUid: "coach", name: "x" }));
  });
});

// Approved 2026-11-24 (single games): teams/{teamId}/games.
//   R11 members read the team's single games; outsiders and removed members can't
//   R12 the creator and Schedulers add, edit and delete; Families can't; the
//       team id must match
const single = (extra = {}) => ({ teamId: TEAM, kind: "scrimmage", opponent: "Hawks", canceled: false, ...extra });

describe("R11 reading single games", () => {
  beforeEach(() => put(`teams/${TEAM}/games/g1`, single()));

  it("the creator and every member read them", async () => {
    for (const uid of ["coach", "helper", "family"]) {
      await assertSucceeds(getDoc(doc(db(uid), `teams/${TEAM}/games/g1`)));
      await assertSucceeds(getDocs(collection(db(uid), `teams/${TEAM}/games`)));
    }
  });

  it("outsiders can't", async () => {
    await assertFails(getDoc(doc(db("stranger"), `teams/${TEAM}/games/g1`)));
    await assertFails(getDocs(collection(db("stranger"), `teams/${TEAM}/games`)));
  });

  it("a removed member can't any more", async () => {
    await admin((f) => deleteDoc(doc(f, `teams/${TEAM}/members/family`)));
    await assertFails(getDoc(doc(db("family"), `teams/${TEAM}/games/g1`)));
  });
});

describe("R12 adding, editing and deleting single games", () => {
  beforeEach(() => put(`teams/${TEAM}/games/g1`, single()));

  it("the creator and a Scheduler add, edit and delete", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), `teams/${TEAM}/games/g2`), single({ kind: "game" })));
    await assertSucceeds(setDoc(doc(db("helper"), `teams/${TEAM}/games/g3`), single({ kind: "friendly" })));
    await assertSucceeds(updateDoc(doc(db("helper"), `teams/${TEAM}/games/g1`), { canceled: true }));
    await assertSucceeds(deleteDoc(doc(db("helper"), `teams/${TEAM}/games/g1`)));
    await assertSucceeds(deleteDoc(doc(db("coach"), `teams/${TEAM}/games/g2`)));
  });

  it("a Family can't", async () => {
    await assertFails(setDoc(doc(db("family"), `teams/${TEAM}/games/g2`), single()));
    await assertFails(updateDoc(doc(db("family"), `teams/${TEAM}/games/g1`), { canceled: true }));
    await assertFails(deleteDoc(doc(db("family"), `teams/${TEAM}/games/g1`)));
  });

  it("an outsider can't", async () => {
    await assertFails(setDoc(doc(db("stranger"), `teams/${TEAM}/games/g2`), single()));
    await assertFails(deleteDoc(doc(db("stranger"), `teams/${TEAM}/games/g1`)));
  });

  it("the team id must be this team", async () => {
    await assertFails(setDoc(doc(db("coach"), `teams/${TEAM}/games/g2`), single({ teamId: OTHER })));
    await assertFails(setDoc(doc(db("coach"), `teams/${TEAM}/games/g2`), { kind: "game" }));
  });
});
