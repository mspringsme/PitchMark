// Batch 4 (approved 2026-10-31): every Firestore rule not covered by
// runnerEvents.test.mjs / eventCopies.test.mjs, plus the four fixes the
// user asked for ("fix all"):
//   G1 joining a live room takes a join code / invite for that room
//   G2 adding yourself to a pitcher's sharedWith takes a redeemed invite
//   G3 joining a team takes the creator or a redeemed team invite
//   G4 team invites expire and are single-use
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
  arrayRemove,
  arrayUnion,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";

const LIVE = "live1";
const OTHER_LIVE = "live2";
const GAME = "game1";
const PITCHER = "pitcher1";
const CLAIMED = "pitcher2";
const TEAM = "team1";
const OTHER_TEAM = "team2";

let env;
const db = (uid, token) => env.authenticatedContext(uid, token).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const future = () => Timestamp.fromMillis(Date.now() + 4 * 3600 * 1000);
const past = () => Timestamp.fromMillis(Date.now() - 3600 * 1000);

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
    const put = (path, data) => setDoc(doc(fs, path), data);

    // Accounts
    await put("accountDeletionTombstones/gone", { at: Timestamp.now() });
    await put("users/gone/meta/settings", { a: 1 });
    await put("users/owner/meta/settings", { a: 1 });
    await put("users/owner/liveSessions/live1", { joinCode: "CODE1" });
    await put("users/owner/displayState/current", { pitch: "FB" });

    // Store orders
    await put("retailOrders/o1", { firebaseUid: "owner", total: 10 });

    // Templates
    await put("templates/t1", { ownerUid: "owner", sharedWith: ["coach"], name: "Mine" });
    await put("users/owner/templates/t1", { sharedWith: ["coach"], name: "Legacy" });

    // Pitchers
    await put(`pitchers/${PITCHER}`, { ownerUid: "owner", sharedWith: ["coach"], name: "Ace" });
    await put(`pitchers/${CLAIMED}`, { ownerUid: "owner", claimedByUid: "claimer", sharedWith: [], name: "Kid" });
    await put(`pitchers/${PITCHER}/stats/all`, { pitches: 10 });
    await put("pitcherInviteTokens/open", { pitcherId: PITCHER, ownerUid: "owner", expiresAt: future() });
    await put("pitcherInviteTokens/expired", { pitcherId: PITCHER, ownerUid: "owner", expiresAt: past() });
    await put("pitcherInviteTokens/mine", { pitcherId: PITCHER, ownerUid: "owner", expiresAt: future(), redeemedByUid: "newcoach" });
    await put("pitcherInviteTokens/mineExpired", { pitcherId: PITCHER, ownerUid: "owner", expiresAt: past(), redeemedByUid: "newcoach" });
    await put("pitcherInviteTokens/theirs", { pitcherId: PITCHER, ownerUid: "owner", expiresAt: future(), redeemedByUid: "someoneelse" });
    await put("pitcherInviteTokens/otherPitcher", { pitcherId: CLAIMED, ownerUid: "owner", expiresAt: future(), redeemedByUid: "newcoach" });

    // Players / hitters
    await put("players/p1", { ownerUid: "owner", name: "Kid" });
    await put("hitters/h1", { ownerUid: "owner", name: "Kid" });

    // Teams
    await put(`teams/${TEAM}`, { createdByUid: "creator", name: "Tigers" });
    await put(`teams/${OTHER_TEAM}`, { createdByUid: "creator", name: "Lions" });
    await put(`teams/${TEAM}/members/creator`, { uid: "creator", roles: ["coach"], addedByUid: "creator" });
    await put(`teams/${TEAM}/members/member`, { uid: "member", roles: ["parent"], addedByUid: "creator" });
    await put(`teams/${TEAM}/players/kid`, { name: "Kid" });
    const invite = (extra) => ({ teamId: TEAM, roles: ["parent"], createdByUid: "creator", expiresAt: future(), ...extra });
    await put("teamInviteTokens/open", invite({}));
    await put("teamInviteTokens/expired", invite({ expiresAt: past() }));
    await put("teamInviteTokens/mine", invite({ redeemedByUid: "joiner" }));
    await put("teamInviteTokens/mineExpired", invite({ redeemedByUid: "joiner", expiresAt: past() }));
    await put("teamInviteTokens/mineCoach", invite({ redeemedByUid: "joiner", roles: ["coach", "parent"] }));
    await put("teamInviteTokens/theirs", invite({ redeemedByUid: "someoneelse" }));
    await put("teamInviteTokens/otherTeam", invite({ teamId: OTHER_TEAM, redeemedByUid: "joiner" }));

    // Live rooms and their credentials
    await put(`liveGames/${LIVE}`, {
      ownerUid: "owner", status: "active", ownerGameId: GAME,
      createdAt: Timestamp.fromMillis(1_000), expiresAt: future(), balls: 0,
    });
    await put(`liveGames/${OTHER_LIVE}`, {
      ownerUid: "owner", status: "active", ownerGameId: "game2",
      createdAt: Timestamp.fromMillis(1_000), expiresAt: future(),
    });
    await put(`liveGames/${LIVE}/participants/partner`, { uid: "partner" });
    await put(`liveGames/${LIVE}/displayParticipants/display`, { uid: "display" });
    await put("users/dsession/meta/activeSession", { mode: "displayOnly", liveId: LIVE, deviceId: "d1" });
    for (const col of ["joinCodes", "inviteTokens", "displayInviteTokens"]) {
      await put(`${col}/GOOD`, { ownerUid: "owner", liveId: LIVE, expiresAt: future() });
      await put(`${col}/OLD`, { ownerUid: "owner", liveId: LIVE, expiresAt: past() });
      await put(`${col}/ELSEWHERE`, { ownerUid: "owner", liveId: OTHER_LIVE, expiresAt: future() });
    }

    // Owner's game, reachable by partners through its active join code
    await put(`users/owner/games/${GAME}`, { opponent: "Demo", activeSessionCode: "GOOD" });
    await put(`users/owner/games/expiredCode`, { opponent: "Demo", activeSessionCode: "OLD" });
  });
});

const ended = (liveId = LIVE) =>
  env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), `liveGames/${liveId}`), { status: "ended" }));

// ─────────────────────────────────────────────

describe("accounts (rules 1-3)", () => {
  it("1 an account being deleted is refused everywhere, even its own data", async () => {
    await assertFails(getDoc(doc(db("gone"), "users/gone/meta/settings")));
    await assertFails(setDoc(doc(db("gone"), "users/gone/meta/settings"), { a: 2 }));
    await assertFails(setDoc(doc(db("gone"), "pitchers/new"), { ownerUid: "gone" }));
  });

  it("2 nobody can read or write the deletion markers", async () => {
    await assertFails(getDoc(doc(db("gone"), "accountDeletionTombstones/gone")));
    await assertFails(deleteDoc(doc(db("gone"), "accountDeletionTombstones/gone")));
    await assertFails(setDoc(doc(db("owner"), "accountDeletionTombstones/owner"), { at: Timestamp.now() }));
  });

  it("3 a user's own area is theirs alone", async () => {
    for (const path of ["users/owner/meta/settings", "users/owner/liveSessions/live1", "users/owner/displayState/current", "users/owner/meta/archive"]) {
      await assertSucceeds(setDoc(doc(db("owner"), path), { b: 1 }, { merge: true }));
      await assertSucceeds(getDoc(doc(db("owner"), path)));
      await assertFails(getDoc(doc(db("partner"), path)));
      await assertFails(setDoc(doc(db("partner"), path), { b: 2 }));
    }
    await assertFails(getDoc(doc(anon(), "users/owner/meta/settings")));
  });
});

describe("store orders (rule 4)", () => {
  it("buyer reads only their own; no app creates one; only an admin changes one", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), "retailOrders/o1")));
    await assertFails(getDoc(doc(db("stranger"), "retailOrders/o1")));
    await assertFails(setDoc(doc(db("owner"), "retailOrders/o2"), { firebaseUid: "owner" }));
    await assertFails(updateDoc(doc(db("owner"), "retailOrders/o1"), { total: 0 }));
    await assertFails(deleteDoc(doc(db("owner"), "retailOrders/o1")));
    await assertSucceeds(updateDoc(doc(db("admin", { admin: true }), "retailOrders/o1"), { status: "shipped" }));
    await assertSucceeds(getDoc(doc(db("admin", { admin: true }), "retailOrders/o1")));
  });
});

describe("templates (rule 5)", () => {
  it("owner and shared users read; only the owner writes", async () => {
    for (const path of ["templates/t1", "users/owner/templates/t1"]) {
      await assertSucceeds(getDoc(doc(db("owner"), path)));
      await assertSucceeds(getDoc(doc(db("coach"), path)));
      await assertFails(getDoc(doc(db("stranger"), path)));
      await assertFails(updateDoc(doc(db("coach"), path), { name: "Hijacked" }));
      await assertSucceeds(updateDoc(doc(db("owner"), path), { name: "Renamed" }));
    }
    await assertSucceeds(setDoc(doc(db("coach"), "templates/t2"), { ownerUid: "coach" }));
    await assertFails(setDoc(doc(db("coach"), "templates/t3"), { ownerUid: "owner" }));
    await assertFails(deleteDoc(doc(db("coach"), "templates/t1")));
  });
});

describe("pitchers (rules 6-10)", () => {
  const P = `pitchers/${PITCHER}`;
  const C = `pitchers/${CLAIMED}`;

  it("6 owner, shared coach and claimer read; stranger doesn't", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), P)));
    await assertSucceeds(getDoc(doc(db("coach"), P)));
    await assertSucceeds(getDoc(doc(db("claimer"), C)));
    await assertFails(getDoc(doc(db("stranger"), P)));
  });

  it("7 a pitcher can be created only as yourself", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "pitchers/new"), { ownerUid: "coach" }));
    await assertFails(setDoc(doc(db("coach"), "pitchers/new2"), { ownerUid: "owner" }));
  });

  it("8 owner and active owner change anything; a coach only claims, for themselves", async () => {
    await assertSucceeds(updateDoc(doc(db("owner"), P), { name: "Renamed" }));
    await assertSucceeds(updateDoc(doc(db("claimer"), C), { name: "Renamed" }));
    await assertFails(updateDoc(doc(db("coach"), P), { name: "Hijacked" }));
    await assertFails(updateDoc(doc(db("coach"), P), { claimedByUid: "stranger" }));
    await assertSucceeds(updateDoc(doc(db("coach"), P), { claimedByUid: "coach" }));
    await assertFails(updateDoc(doc(db("stranger"), P), { name: "Hijacked" }));
  });

  it("G2 adding yourself to sharedWith takes an invite for this pitcher you redeemed", async () => {
    const join = (uid, token) =>
      setDoc(doc(db(uid), P), { sharedWith: arrayUnion(uid), ...(token ? { inviteToken: token } : {}) }, { merge: true });
    await assertFails(join("newcoach"), "knowing the id is not enough");
    await assertFails(join("newcoach", "open"), "an invite nobody has redeemed");
    await assertFails(join("newcoach", "theirs"), "an invite someone else redeemed");
    await assertFails(join("newcoach", "otherPitcher"), "an invite for another pitcher");
    await assertFails(join("newcoach", "mineExpired"), "an expired invite");
    await assertFails(join("newcoach", "nosuchtoken"), "an invite that doesn't exist");
    await assertSucceeds(join("newcoach", "mine"));
    await assertSucceeds(join("newcoach", "mine"), "re-opening your own link is harmless");
  });

  it("G2 joining can't remove anyone or change anything else", async () => {
    await assertFails(setDoc(doc(db("newcoach"), P),
      { sharedWith: ["newcoach"], inviteToken: "mine" }, { merge: true }), "drops coach");
    await assertFails(setDoc(doc(db("newcoach"), P),
      { sharedWith: arrayUnion("newcoach"), inviteToken: "mine", name: "Hijacked" }, { merge: true }));
    await assertFails(updateDoc(doc(db("coach"), P), { sharedWith: arrayRemove("coach") }),
      "even removing yourself is not a join");
  });

  it("9 only the owner deletes a pitcher", async () => {
    await assertFails(deleteDoc(doc(db("claimer"), C)));
    await assertFails(deleteDoc(doc(db("coach"), P)));
    await assertSucceeds(deleteDoc(doc(db("owner"), P)));
  });

  it("10 stats: readers read, only the server writes", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), `${P}/stats/all`)));
    await assertSucceeds(getDoc(doc(db("coach"), `${P}/stats/all`)));
    await assertFails(getDoc(doc(db("stranger"), `${P}/stats/all`)));
    await assertFails(setDoc(doc(db("owner"), `${P}/stats/all`), { pitches: 999 }));
  });
});

describe("pitcher invites (rule 11)", () => {
  it("anyone reads an unexpired invite; an expired one only its owner", async () => {
    await assertSucceeds(getDoc(doc(db("stranger"), "pitcherInviteTokens/open")));
    await assertFails(getDoc(doc(db("stranger"), "pitcherInviteTokens/expired")));
    await assertSucceeds(getDoc(doc(db("owner"), "pitcherInviteTokens/expired")));
  });

  it("owner creates, lists and revokes their own", async () => {
    await assertSucceeds(setDoc(doc(db("owner"), "pitcherInviteTokens/new"), { ownerUid: "owner", pitcherId: PITCHER }));
    await assertFails(setDoc(doc(db("coach"), "pitcherInviteTokens/new2"), { ownerUid: "owner", pitcherId: PITCHER }));
    await assertFails(setDoc(doc(db("owner"), "pitcherInviteTokens/new3"), { ownerUid: "owner" }), "must name a pitcher");
    await assertSucceeds(getDocs(query(collection(db("owner"), "pitcherInviteTokens"), where("ownerUid", "==", "owner"))));
    await assertFails(getDocs(collection(db("owner"), "pitcherInviteTokens")));
    await assertFails(deleteDoc(doc(db("stranger"), "pitcherInviteTokens/open")));
    await assertSucceeds(deleteDoc(doc(db("owner"), "pitcherInviteTokens/open")));
  });

  it("the redeemer marks it used once, as themselves, changing nothing else", async () => {
    await assertFails(updateDoc(doc(db("newcoach"), "pitcherInviteTokens/open"), { redeemedByUid: "other" }));
    await assertFails(updateDoc(doc(db("newcoach"), "pitcherInviteTokens/open"),
      { redeemedByUid: "newcoach", pitcherId: CLAIMED }));
    await assertSucceeds(updateDoc(doc(db("newcoach"), "pitcherInviteTokens/open"),
      { redeemedByUid: "newcoach", redeemedAt: Timestamp.now() }));
    await assertFails(updateDoc(doc(db("third"), "pitcherInviteTokens/open"), { redeemedByUid: "third" }),
      "already used");
  });
});

describe("players and hitters (rule 12)", () => {
  it("owner only", async () => {
    for (const path of ["players/p1", "hitters/h1"]) {
      await assertSucceeds(getDoc(doc(db("owner"), path)));
      await assertSucceeds(updateDoc(doc(db("owner"), path), { name: "Renamed" }));
      await assertFails(getDoc(doc(db("coach"), path)));
      await assertFails(updateDoc(doc(db("coach"), path), { name: "Hijacked" }));
    }
    await assertSucceeds(setDoc(doc(db("coach"), "players/p2"), { ownerUid: "coach" }));
    await assertFails(setDoc(doc(db("coach"), "hitters/h2"), { ownerUid: "owner" }));
  });
});

describe("teams (rules 13-18)", () => {
  const T = `teams/${TEAM}`;

  it("13-16 creator and members read; nobody lists; creator changes; nobody deletes", async () => {
    await assertSucceeds(getDoc(doc(db("creator"), T)));
    await assertSucceeds(getDoc(doc(db("member"), T)));
    await assertFails(getDoc(doc(db("stranger"), T)));
    await assertFails(getDocs(collection(db("creator"), "teams")));
    await assertSucceeds(updateDoc(doc(db("creator"), T), { name: "Renamed" }));
    await assertFails(updateDoc(doc(db("member"), T), { name: "Hijacked" }));
    await assertFails(deleteDoc(doc(db("creator"), T)));
    await assertSucceeds(setDoc(doc(db("coach"), "teams/new"), { createdByUid: "coach" }));
    await assertFails(setDoc(doc(db("coach"), "teams/new2"), { createdByUid: "creator" }));
  });

  it("17 members: own entry or creator reads; creator changes roles; leave or be removed", async () => {
    await assertSucceeds(getDoc(doc(db("member"), `${T}/members/member`)));
    await assertSucceeds(getDoc(doc(db("creator"), `${T}/members/member`)));
    await assertFails(getDoc(doc(db("member"), `${T}/members/creator`)));
    await assertFails(updateDoc(doc(db("member"), `${T}/members/member`), { roles: ["coach"] }));
    await assertSucceeds(updateDoc(doc(db("creator"), `${T}/members/member`), { roles: ["coach"] }));
    await assertSucceeds(deleteDoc(doc(db("member"), `${T}/members/member`)));
    await assertFails(deleteDoc(doc(db("stranger"), `${T}/members/creator`)));
  });

  it("17 'my teams' returns only your own memberships", async () => {
    await assertSucceeds(getDocs(query(collectionGroup(db("member"), "members"), where("uid", "==", "member"))));
    await assertFails(getDocs(query(collectionGroup(db("member"), "members"), where("uid", "==", "creator"))));
    await assertFails(getDocs(collectionGroup(db("member"), "members")));
  });

  it("G3 the creator can add themselves; knowing a team's id is not enough", async () => {
    await assertSucceeds(setDoc(doc(db("creator"), `teams/${OTHER_TEAM}/members/creator`),
      { uid: "creator", roles: ["coach"], addedByUid: "creator" }));
    await assertFails(setDoc(doc(db("stranger"), `${T}/members/stranger`),
      { uid: "stranger", roles: ["coach"], addedByUid: "stranger" }));
    await assertFails(setDoc(doc(db("stranger"), `${T}/members/member2`),
      { uid: "member2", roles: ["parent"], addedByUid: "stranger" }), "never someone else's entry");
  });

  it("G3 joining takes a team invite you redeemed, with no role it didn't grant", async () => {
    const join = (token, roles = ["parent"]) =>
      setDoc(doc(db("joiner"), `${T}/members/joiner`), { uid: "joiner", roles, addedByUid: "creator", inviteToken: token });
    await assertFails(join("open"), "not redeemed");
    await assertFails(join("theirs"), "someone else redeemed it");
    await assertFails(join("otherTeam"), "for another team");
    await assertFails(join("mineExpired"), "expired");
    await assertFails(join("mine", ["coach"]), "a role the invite didn't grant");
    await assertSucceeds(join("mine"));
  });

  it("G3 an invite granting coach can make you a coach", async () => {
    await assertSucceeds(setDoc(doc(db("joiner"), `${T}/members/joiner`),
      { uid: "joiner", roles: ["coach"], addedByUid: "creator", inviteToken: "mineCoach" }));
  });

  it("18 roster: members read, only the creator changes it", async () => {
    await assertSucceeds(getDoc(doc(db("member"), `${T}/players/kid`)));
    await assertFails(getDoc(doc(db("stranger"), `${T}/players/kid`)));
    await assertFails(updateDoc(doc(db("member"), `${T}/players/kid`), { name: "Hijacked" }));
    await assertSucceeds(updateDoc(doc(db("creator"), `${T}/players/kid`), { name: "Renamed" }));
  });
});

describe("team invites (rule 19 + G4)", () => {
  it("only the creator creates one, naming a team and an expiry", async () => {
    await assertSucceeds(setDoc(doc(db("creator"), "teamInviteTokens/new"),
      { createdByUid: "creator", teamId: TEAM, roles: ["parent"], expiresAt: future() }));
    await assertFails(setDoc(doc(db("creator"), "teamInviteTokens/new2"),
      { createdByUid: "creator", teamId: TEAM, roles: ["parent"] }), "no expiry");
    await assertFails(setDoc(doc(db("stranger"), "teamInviteTokens/new3"),
      { createdByUid: "creator", teamId: TEAM, expiresAt: future() }));
    await assertFails(getDocs(collection(db("creator"), "teamInviteTokens")));
    await assertSucceeds(deleteDoc(doc(db("creator"), "teamInviteTokens/open")));
    await assertFails(deleteDoc(doc(db("stranger"), "teamInviteTokens/expired")));
  });

  it("G4 anyone reads an unexpired invite; an expired one only its creator", async () => {
    await assertSucceeds(getDoc(doc(db("stranger"), "teamInviteTokens/open")));
    await assertFails(getDoc(doc(db("stranger"), "teamInviteTokens/expired")));
    await assertSucceeds(getDoc(doc(db("creator"), "teamInviteTokens/expired")));
  });

  it("G4 the redeemer marks it used once, as themselves; never an expired one", async () => {
    const burn = (uid, token, extra = {}) =>
      updateDoc(doc(db(uid), `teamInviteTokens/${token}`), { redeemedByUid: uid, redeemedAt: Timestamp.now(), ...extra });
    await assertFails(burn("joiner", "expired"));
    await assertFails(burn("joiner", "open", { roles: ["coach"] }), "can't change what it grants");
    await assertFails(updateDoc(doc(db("joiner"), "teamInviteTokens/open"), { redeemedByUid: "other" }));
    await assertSucceeds(burn("joiner", "open"));
    await assertFails(burn("third", "open"), "already used");
  });
});

describe("join codes and invites (rule 20)", () => {
  for (const col of ["joinCodes", "inviteTokens", "displayInviteTokens"]) {
    it(`${col}: read unexpired; create as yourself with room + expiry; owner changes; owner-scoped list`, async () => {
      await assertSucceeds(getDoc(doc(db("stranger"), `${col}/GOOD`)));
      await assertFails(getDoc(doc(db("stranger"), `${col}/OLD`)));
      await assertSucceeds(getDoc(doc(db("owner"), `${col}/OLD`)));
      await assertSucceeds(getDoc(doc(db("stranger"), `${col}/MISSING`)), "a code that doesn't exist reads as absent");

      await assertSucceeds(setDoc(doc(db("owner"), `${col}/NEW`), { ownerUid: "owner", liveId: LIVE, expiresAt: future() }));
      await assertFails(setDoc(doc(db("owner"), `${col}/NEW2`), { ownerUid: "owner", liveId: LIVE }), "no expiry");
      await assertFails(setDoc(doc(db("owner"), `${col}/NEW3`), { ownerUid: "owner", expiresAt: future() }), "no room");
      await assertFails(setDoc(doc(db("partner"), `${col}/NEW4`), { ownerUid: "owner", liveId: LIVE, expiresAt: future() }));

      await assertSucceeds(updateDoc(doc(db("owner"), `${col}/GOOD`), { expiresAt: future() }));
      await assertFails(updateDoc(doc(db("partner"), `${col}/GOOD`), { liveId: OTHER_LIVE }));
      await assertFails(deleteDoc(doc(db("partner"), `${col}/GOOD`)));

      await assertSucceeds(getDocs(query(collection(db("owner"), col), where("ownerUid", "==", "owner"))));
      await assertFails(getDocs(collection(db("owner"), col)));
      await assertFails(getDocs(query(collection(db("partner"), col), where("ownerUid", "==", "owner"))));
    });
  }
});

describe("live rooms (rule 21)", () => {
  const L = `liveGames/${LIVE}`;

  it("owner, partner, display device and a display-only session read; nobody else; nobody lists", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), L)));
    await assertSucceeds(getDoc(doc(db("partner"), L)));
    await assertSucceeds(getDoc(doc(db("display"), L)));
    await assertSucceeds(getDoc(doc(db("dsession"), L)));
    await assertFails(getDoc(doc(db("dsession"), `liveGames/${OTHER_LIVE}`)), "a display session for another room");
    await assertFails(getDoc(doc(db("stranger"), L)));
    await assertFails(getDocs(collection(db("owner"), "liveGames")));
  });

  it("a room is created only as yourself, active", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "liveGames/new"), { ownerUid: "coach", status: "active" }));
    await assertFails(setDoc(doc(db("coach"), "liveGames/new2"), { ownerUid: "coach", status: "ended" }));
    await assertFails(setDoc(doc(db("coach"), "liveGames/new3"), { ownerUid: "owner", status: "active" }));
  });

  it("a partner changes game fields, never owner/status/created/game/expiry", async () => {
    await assertSucceeds(updateDoc(doc(db("partner"), L), { balls: 2 }));
    for (const [field, value] of [["ownerUid", "partner"], ["status", "ended"], ["createdAt", Timestamp.now()],
      ["ownerGameId", "other"], ["expiresAt", future()]]) {
      await assertFails(updateDoc(doc(db("partner"), L), { [field]: value }), field);
    }
    await assertFails(updateDoc(doc(db("display"), L), { balls: 3 }));
    await assertFails(updateDoc(doc(db("stranger"), L), { balls: 3 }));
  });

  it("only the owner ends, renews or deletes the room", async () => {
    await assertSucceeds(updateDoc(doc(db("owner"), L), { expiresAt: future() }));
    await assertFails(deleteDoc(doc(db("partner"), L)));
    await assertSucceeds(updateDoc(doc(db("owner"), L), { status: "ended" }));
    await assertSucceeds(deleteDoc(doc(db("owner"), L)));
  });

  it("G1 joining takes a code or invite for this room that hasn't expired", async () => {
    const join = (fields) => setDoc(doc(db("newpartner"), `${L}/participants/newpartner`), { uid: "newpartner", ...fields });
    await assertFails(join({}), "knowing the room id is not enough");
    await assertFails(join({ joinCode: "OLD" }), "expired code");
    await assertFails(join({ joinCode: "ELSEWHERE" }), "another room's code");
    await assertFails(join({ joinCode: "MISSING" }), "a code that doesn't exist");
    await assertFails(join({ inviteToken: "OLD" }), "expired invite");
    await assertFails(join({ displayInviteToken: "GOOD" }), "a display invite doesn't make a partner");
    await assertSucceeds(join({ joinCode: "GOOD" }));
  });

  it("G1 an invite link works too, and the owner needs nothing", async () => {
    await assertSucceeds(setDoc(doc(db("newpartner"), `${L}/participants/newpartner`),
      { uid: "newpartner", inviteToken: "GOOD" }));
    await assertSucceeds(setDoc(doc(db("owner"), `${L}/participants/owner`), { uid: "owner" }));
  });

  it("G1 a display device joins only with a display invite", async () => {
    const join = (fields) => setDoc(doc(db("newdisplay"), `${L}/displayParticipants/newdisplay`), { uid: "newdisplay", ...fields });
    await assertFails(join({}));
    await assertFails(join({ joinCode: "GOOD" }));
    await assertFails(join({ displayInviteToken: "OLD" }));
    await assertSucceeds(join({ displayInviteToken: "GOOD" }));
  });

  it("G1 nobody can create someone else's presence", async () => {
    await assertFails(setDoc(doc(db("partner"), `${L}/participants/friend`), { uid: "friend", joinCode: "GOOD" }));
  });

  it("presence updates: your own, presence fields only (the heartbeat)", async () => {
    await assertSucceeds(setDoc(doc(db("partner"), `${L}/participants/partner`),
      { uid: "partner", lastSeenAt: Timestamp.now(), joinCode: "GOOD" }, { merge: true }));
    await assertFails(setDoc(doc(db("partner"), `${L}/participants/partner`), { role: "owner" }, { merge: true }));
    await assertFails(updateDoc(doc(db("stranger"), `${L}/participants/partner`), { lastSeenAt: Timestamp.now() }));
  });

  it("presence removal and listing", async () => {
    await assertSucceeds(getDoc(doc(db("owner"), `${L}/participants/partner`)));
    await assertSucceeds(getDoc(doc(db("partner"), `${L}/participants/partner`)));
    await assertFails(getDoc(doc(db("stranger"), `${L}/participants/partner`)));
    await assertSucceeds(deleteDoc(doc(db("owner"), `${L}/participants/partner`)), "the owner removes a partner");
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${L}/participants/partner`), { uid: "partner" }));
    await assertSucceeds(getDocs(collection(db("partner"), `${L}/participants`)));
    await assertFails(getDocs(collection(db("stranger"), `${L}/participants`)));
    await assertSucceeds(getDocs(collection(db("owner"), `${L}/displayParticipants`)));
    await assertFails(getDocs(collection(db("partner"), `${L}/displayParticipants`)));
    await assertFails(deleteDoc(doc(db("stranger"), `${L}/participants/partner`)));
    await assertSucceeds(deleteDoc(doc(db("owner"), `${L}/displayParticipants/display`)));
    await assertSucceeds(deleteDoc(doc(db("partner"), `${L}/participants/partner`)));
  });
});

describe("owner's games (rule 22)", () => {
  const G = `users/owner/games/${GAME}`;

  it("owner has full access; a partner reads that game while its code and room are live", async () => {
    await assertSucceeds(updateDoc(doc(db("owner"), G), { opponent: "Renamed" }));
    await assertSucceeds(getDoc(doc(db("partner"), G)));
    await assertFails(updateDoc(doc(db("partner"), G), { opponent: "Hijacked" }));
    await assertFails(getDoc(doc(db("stranger"), G)));
    await assertFails(getDocs(collection(db("partner"), "users/owner/games")));
  });

  it("an expired code cuts the partner off", async () => {
    await assertFails(getDoc(doc(db("partner"), "users/owner/games/expiredCode")));
  });

  it("an ended room cuts the partner off", async () => {
    await ended();
    await assertFails(getDoc(doc(db("partner"), G)));
  });
});

// Batch 7 (approved 2026-11-01): the deletes and writes a merge makes.
describe("merge cleanup (batch 7 rule 17)", () => {
  const T = `teams/${TEAM}`;

  it("only the team's creator removes a roster row", async () => {
    await assertFails(deleteDoc(doc(db("member"), `${T}/players/kid`)));
    await assertFails(deleteDoc(doc(db("stranger"), `${T}/players/kid`)));
    await assertSucceeds(deleteDoc(doc(db("creator"), `${T}/players/kid`)));
  });

  it("only a player record's owner changes its linked histories or deletes it", async () => {
    await assertFails(updateDoc(doc(db("coach"), "players/p1"), { linkedPitcherIds: arrayUnion("x") }));
    await assertSucceeds(updateDoc(doc(db("owner"), "players/p1"), { linkedPitcherIds: arrayUnion("x"), linkedHitterIds: arrayUnion("y") }));
    await assertFails(deleteDoc(doc(db("coach"), "players/p1")));
    await assertSucceeds(deleteDoc(doc(db("owner"), "players/p1")));
  });

  it("only a hitter record's owner checks its history or deletes it", async () => {
    await assertSucceeds(getDocs(collection(db("owner"), "hitters/h1/runnerEvents")));
    await assertSucceeds(getDocs(collection(db("owner"), "hitters/h1/pitchEvents")));
    await assertFails(getDocs(collection(db("coach"), "hitters/h1/runnerEvents")));
    await assertFails(deleteDoc(doc(db("coach"), "hitters/h1")));
    await assertSucceeds(deleteDoc(doc(db("owner"), "hitters/h1")));
  });
});
