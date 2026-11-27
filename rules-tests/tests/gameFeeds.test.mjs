// Game feeds and team followers (approved 2026-11-24, clip brief phase 4):
//   1 joining as a follower: only yourself, with an unexpired follower code
//     for this team, arriving pending; only the creator makes follower codes
//   2 the creator approves or removes followers; a follower can leave but
//     can't approve themselves
//   3 a follower is not a member: no roster, card sets, team tourneys,
//     members list, live rooms or game pitches
//   4 creating a feed: as yourself, for a team you're on; official only by
//     the team's creator
//   5 only the scorer changes or deletes a feed; team, owner and kind fixed
//   6 reading a feed: the scorer; an approved follower of that feed; or,
//     audience team, members and approved team followers; nobody but the
//     scorer once the coach switches feeds off
//   7 listing a game's feeds: members and approved team followers
//   8 feed events: only the scorer writes, only the outcome fields; read
//     as in 6
//   9 asking to follow a feed: yourself, arriving requested, only if on the
//     team; the scorer approves or removes; you can leave
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
  Timestamp, collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where,
} from "firebase/firestore";

const TEAM = "reds";
const OTHER = "hawks";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const put = (path, data) => admin((f) => setDoc(doc(f, path), data));
const future = () => Timestamp.fromMillis(Date.now() + 86_400_000);
const past = () => Timestamp.fromMillis(Date.now() - 86_400_000);

const followerCode = (extra = {}) => ({
  teamId: TEAM, roles: ["follower"], createdByUid: "coach", multiUse: true, expiresAt: future(), ...extra,
});
const joinAs = (uid, inviteToken = "fol") => ({ uid, name: uid, status: "pending", inviteToken });
const feed = (extra = {}) => ({
  ownerUid: "coach", teamId: TEAM, scheduledGameId: "g1", gameLabel: "vs. Hawks", title: "Coach",
  kind: "official", audience: "team", scope: "everything", showLastNames: false, status: "live", ...extra,
});
const event = (extra = {}) => ({ at: Timestamp.now(), inning: 1, batter: "Juju", kind: "ball", text: "Ball 1-0", runs: 0, ...extra });

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
  await put(`teams/${TEAM}/members/family`, { uid: "family", roles: ["parent"], addedByUid: "coach", inviteToken: "fam" });
  await put(`teams/${TEAM}/followers/gran`, { uid: "gran", name: "Gran", status: "approved", inviteToken: "fol" });
  await put(`teams/${TEAM}/followers/pend`, { uid: "pend", name: "Pend", status: "pending", inviteToken: "fol" });
  await put("teamInviteTokens/fol", followerCode());
  await put("teamInviteTokens/folOld", followerCode({ expiresAt: past() }));
  await put("teamInviteTokens/folHawks", followerCode({ teamId: OTHER, createdByUid: "othercoach" }));
  await put("teamInviteTokens/fam", { teamId: TEAM, roles: ["parent"], createdByUid: "coach", multiUse: true, expiresAt: future() });
  await put("gameFeeds/f1", feed());
  await put("gameFeeds/f1/events/e1", event());
  await put("gameFeeds/p1", feed({ ownerUid: "family", kind: "personal", title: "Mrs. Jones", audience: "approved" }));
  await put("gameFeeds/p1/feedFollowers/gran", { uid: "gran", name: "Gran", status: "approved" });
  await put("gameFeeds/p1/events/e1", event());
  await put("gameFeeds/n1", feed({ ownerUid: "family", kind: "personal", title: "Private", audience: "nobody" }));
});

describe("1 joining as a follower", () => {
  it("joins with the team's follower code, pending", async () => {
    await assertSucceeds(setDoc(doc(db("newgran"), `teams/${TEAM}/followers/newgran`), joinAs("newgran")));
  });

  it("not approved straight away", async () => {
    await assertFails(setDoc(doc(db("newgran"), `teams/${TEAM}/followers/newgran`),
      { ...joinAs("newgran"), status: "approved" }));
  });

  it("not as someone else", async () => {
    await assertFails(setDoc(doc(db("newgran"), `teams/${TEAM}/followers/other`), joinAs("other")));
  });

  it("not with an expired code, another team's code, a family code or no code", async () => {
    const f = db("newgran");
    await assertFails(setDoc(doc(f, `teams/${TEAM}/followers/newgran`), joinAs("newgran", "folOld")));
    await assertFails(setDoc(doc(f, `teams/${TEAM}/followers/newgran`), joinAs("newgran", "folHawks")));
    await assertFails(setDoc(doc(f, `teams/${TEAM}/followers/newgran`), joinAs("newgran", "fam")));
    await assertFails(setDoc(doc(f, `teams/${TEAM}/followers/newgran`), { uid: "newgran", name: "x", status: "pending" }));
  });

  it("a follower code never makes a member", async () => {
    await assertFails(setDoc(doc(db("newgran"), `teams/${TEAM}/members/newgran`),
      { uid: "newgran", roles: ["follower"], inviteToken: "fol", name: "x" }));
    await assertFails(setDoc(doc(db("newgran"), `teams/${TEAM}/members/newgran`),
      { uid: "newgran", roles: ["parent"], inviteToken: "fol", name: "x" }));
  });

  it("only the creator makes follower codes, and they're reusable follower-only codes", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "teamInviteTokens/new"), followerCode()));
    await assertFails(setDoc(doc(db("family"), "teamInviteTokens/new2"), followerCode({ createdByUid: "family" })));
    await assertFails(setDoc(doc(db("coach"), "teamInviteTokens/new3"), followerCode({ multiUse: false })));
    await assertFails(setDoc(doc(db("coach"), "teamInviteTokens/new4"), followerCode({ roles: ["follower", "parent"] })));
  });
});

describe("2 approving followers", () => {
  it("the creator approves and removes", async () => {
    await assertSucceeds(updateDoc(doc(db("coach"), `teams/${TEAM}/followers/pend`), { status: "approved" }));
    await assertSucceeds(deleteDoc(doc(db("coach"), `teams/${TEAM}/followers/gran`)));
  });

  it("the creator lists followers; nobody else does", async () => {
    await assertSucceeds(getDocs(collection(db("coach"), `teams/${TEAM}/followers`)));
    await assertFails(getDocs(collection(db("family"), `teams/${TEAM}/followers`)));
    await assertFails(getDocs(collection(db("gran"), `teams/${TEAM}/followers`)));
  });

  it("a follower can't approve themselves or anyone", async () => {
    await assertFails(updateDoc(doc(db("pend"), `teams/${TEAM}/followers/pend`), { status: "approved" }));
    await assertFails(updateDoc(doc(db("family"), `teams/${TEAM}/followers/pend`), { status: "approved" }));
  });

  it("a follower can leave", async () => {
    await assertSucceeds(deleteDoc(doc(db("gran"), `teams/${TEAM}/followers/gran`)));
  });

  it("a follower finds their own teams", async () => {
    const q = query(collectionGroup(db("gran"), "followers"), where("uid", "==", "gran"));
    await assertSucceeds(getDocs(q));
  });
});

describe("3 a follower is not a member", () => {
  beforeEach(async () => {
    await put(`teams/${TEAM}/players/p1`, { name: "Juju", jerseyNumber: "12" });
    await put(`teams/${TEAM}/cardSets/s1`, { organizerUid: "coach", status: "open", name: "Set" });
    await put(`teams/${TEAM}/tourneys/t1`, { name: "Summer Slam", teamId: TEAM, games: [] });
    await put("liveGames/room1", { ownerUid: "coach", status: "active" });
    await put("liveGames/room1/pitchEvents/x", { pitch: "Fastball", calledPitch: { pitch: "Fastball" } });
    await put("users/coach/games/g1/pitchEvents/x", { pitch: "Fastball", codes: ["12"] });
  });

  it("reads the team's name, nothing else on the team", async () => {
    const f = db("gran");
    await assertSucceeds(getDoc(doc(f, `teams/${TEAM}`)));
    await assertFails(getDoc(doc(f, `teams/${TEAM}/players/p1`)));
    await assertFails(getDocs(collection(f, `teams/${TEAM}/players`)));
    await assertFails(getDoc(doc(f, `teams/${TEAM}/cardSets/s1`)));
    await assertFails(getDoc(doc(f, `teams/${TEAM}/tourneys/t1`)));
    await assertFails(getDocs(collection(f, `teams/${TEAM}/members`)));
  });

  it("never a live room or the game's pitches", async () => {
    const f = db("gran");
    await assertFails(getDoc(doc(f, "liveGames/room1")));
    await assertFails(getDoc(doc(f, "liveGames/room1/pitchEvents/x")));
    await assertFails(getDoc(doc(f, "users/coach/games/g1/pitchEvents/x")));
  });

  it("a pending follower can't read the team", async () => {
    await assertFails(getDoc(doc(db("pend"), `teams/${TEAM}`)));
  });
});

describe("4 creating a feed", () => {
  it("the creator opens the official feed", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "gameFeeds/new"), feed()));
  });

  it("a member opens a personal feed, not an official one", async () => {
    await assertSucceeds(setDoc(doc(db("family"), "gameFeeds/new"), feed({ ownerUid: "family", kind: "personal" })));
    await assertFails(setDoc(doc(db("family"), "gameFeeds/new2"), feed({ ownerUid: "family", kind: "official" })));
  });

  it("not as someone else, not for a team you're not on, not as a follower", async () => {
    await assertFails(setDoc(doc(db("family"), "gameFeeds/new"), feed({ ownerUid: "coach", kind: "personal" })));
    await assertFails(setDoc(doc(db("family"), "gameFeeds/new"), feed({ ownerUid: "family", kind: "personal", teamId: OTHER })));
    await assertFails(setDoc(doc(db("gran"), "gameFeeds/new"), feed({ ownerUid: "gran", kind: "personal" })));
  });

  it("only the known fields and settings", async () => {
    await assertFails(setDoc(doc(db("coach"), "gameFeeds/new"), feed({ calledPitch: "Fastball" })));
    await assertFails(setDoc(doc(db("coach"), "gameFeeds/new"), feed({ audience: "everyone" })));
  });
});

describe("5 changing a feed", () => {
  it("the scorer changes settings and deletes", async () => {
    await assertSucceeds(updateDoc(doc(db("coach"), "gameFeeds/f1"), { audience: "approved", ourScore: 3 }));
    await assertSucceeds(deleteDoc(doc(db("family"), "gameFeeds/p1")));
  });

  it("team, owner and kind never change", async () => {
    const f = db("coach");
    await assertFails(updateDoc(doc(f, "gameFeeds/f1"), { teamId: OTHER }));
    await assertFails(updateDoc(doc(f, "gameFeeds/f1"), { ownerUid: "family" }));
    await assertFails(updateDoc(doc(f, "gameFeeds/f1"), { kind: "personal" }));
  });

  it("nobody else changes or deletes it", async () => {
    await assertFails(updateDoc(doc(db("family"), "gameFeeds/f1"), { title: "Mine" }));
    await assertFails(deleteDoc(doc(db("gran"), "gameFeeds/f1")));
  });
});

describe("6 reading a feed", () => {
  it("audience team: members and approved followers", async () => {
    await assertSucceeds(getDoc(doc(db("family"), "gameFeeds/f1")));
    await assertSucceeds(getDoc(doc(db("gran"), "gameFeeds/f1")));
  });

  it("not a pending follower or an outsider", async () => {
    await assertFails(getDoc(doc(db("pend"), "gameFeeds/f1")));
    await assertFails(getDoc(doc(db("stranger"), "gameFeeds/f1")));
  });

  it("audience approved: the scorer and approved followers of that feed", async () => {
    await assertSucceeds(getDoc(doc(db("family"), "gameFeeds/p1")));
    await assertSucceeds(getDoc(doc(db("gran"), "gameFeeds/p1")));
    await assertFails(getDoc(doc(db("coach"), "gameFeeds/p1")), "the coach isn't on this feed's list");
  });

  it("audience nobody: the scorer only", async () => {
    await assertSucceeds(getDoc(doc(db("family"), "gameFeeds/n1")));
    await assertFails(getDoc(doc(db("gran"), "gameFeeds/n1")));
    await assertFails(getDoc(doc(db("coach"), "gameFeeds/n1")));
  });

  it("a follower removed from the team loses the feed", async () => {
    await admin((f) => deleteDoc(doc(f, `teams/${TEAM}/followers/gran`)));
    await assertFails(getDoc(doc(db("gran"), "gameFeeds/p1")));
    await assertFails(getDoc(doc(db("gran"), "gameFeeds/f1")));
  });

  it("feeds switched off: only the scorer", async () => {
    await put(`teams/${TEAM}`, { createdByUid: "coach", name: "Reds", followerFeedsOff: true });
    await assertFails(getDoc(doc(db("gran"), "gameFeeds/f1")));
    await assertFails(getDoc(doc(db("family"), "gameFeeds/f1")));
    await assertSucceeds(getDoc(doc(db("coach"), "gameFeeds/f1")));
  });
});

describe("7 listing a game's feeds", () => {
  const byTeam = (uid) => query(collection(db(uid), "gameFeeds"), where("teamId", "==", TEAM));

  it("members and approved followers", async () => {
    await assertSucceeds(getDocs(byTeam("family")));
    await assertSucceeds(getDocs(byTeam("gran")));
  });

  it("not a pending follower or an outsider, and never without the team", async () => {
    await assertFails(getDocs(byTeam("pend")));
    await assertFails(getDocs(byTeam("stranger")));
    await assertFails(getDocs(collection(db("gran"), "gameFeeds")));
  });
});

describe("8 feed events", () => {
  it("the scorer writes outcome fields", async () => {
    await assertSucceeds(setDoc(doc(db("coach"), "gameFeeds/f1/events/e2"), event({ kind: "hit", text: "2B", runs: 1, half: "top" })));
    await assertSucceeds(deleteDoc(doc(db("coach"), "gameFeeds/f1/events/e1")));
  });

  it("the batter's number and the card's result lines, three at most", async () => {
    const f = db("coach");
    await assertSucceeds(setDoc(doc(f, "gameFeeds/f1/events/e4"),
      event({ kind: "hit", text: "1B", jersey: "26", detail: ["1B", "Line · Shallow Left"],
        batting: "Hawks", ourScore: 3, theirScore: 2, outs: 2 })));
    await assertSucceeds(updateDoc(doc(f, "gameFeeds/f1"), { ourName: "Reds", theirName: "Hawks" }));
    await assertFails(setDoc(doc(f, "gameFeeds/f1/events/e5"),
      event({ detail: ["a", "b", "c", "d"] })));
    await assertFails(setDoc(doc(f, "gameFeeds/f1/events/e6"), event({ detail: "1B" })));
  });

  it("the play animation's location, ball type and runner moves; four moves at most", async () => {
    const f = db("coach");
    await assertSucceeds(setDoc(doc(f, "gameFeeds/f1/events/e7"),
      event({ kind: "hit", spotX: 0.5, spotY: 0.36, ballType: "line", moves: [{ f: 0, t: 1 }, { f: 2, t: 4 }] })));
    await assertFails(setDoc(doc(f, "gameFeeds/f1/events/e8"),
      event({ moves: [{ f: 0, t: 1 }, { f: 1, t: 2 }, { f: 2, t: 3 }, { f: 3, t: 4 }, { f: 0, t: 1 }] })));
    await assertFails(setDoc(doc(f, "gameFeeds/f1/events/e9"), event({ moves: "1-4" })));
  });

  it("HIGH RISK: no pitch, location, codes, key or estimate", async () => {
    const f = db("coach");
    for (const extra of [{ pitch: "Fastball" }, { location: "Strike Up" }, { codes: ["12"] },
      { calledPitch: { pitch: "Fastball" } }, { templateId: "k1" }, { catcherEstimate: { pitch: "Curve" } }]) {
      await assertFails(setDoc(doc(f, "gameFeeds/f1/events/e3"), event(extra)), JSON.stringify(extra));
    }
  });

  it("nobody else writes", async () => {
    await assertFails(setDoc(doc(db("family"), "gameFeeds/f1/events/e2"), event()));
    await assertFails(setDoc(doc(db("gran"), "gameFeeds/f1/events/e2"), event()));
    await assertFails(deleteDoc(doc(db("family"), "gameFeeds/f1/events/e1")));
  });

  it("read as the feed is", async () => {
    await assertSucceeds(getDocs(collection(db("gran"), "gameFeeds/f1/events")));
    await assertSucceeds(getDocs(collection(db("gran"), "gameFeeds/p1/events")));
    await assertFails(getDocs(collection(db("pend"), "gameFeeds/f1/events")));
    await assertFails(getDocs(collection(db("coach"), "gameFeeds/p1/events")));
  });
});

describe("9 asking to follow a feed", () => {
  const ask = (uid) => ({ uid, name: uid, status: "requested" });

  it("a team follower or member asks, arriving requested", async () => {
    await admin((f) => deleteDoc(doc(f, "gameFeeds/p1/feedFollowers/gran")));
    await assertSucceeds(setDoc(doc(db("gran"), "gameFeeds/p1/feedFollowers/gran"), ask("gran")));
    await assertSucceeds(setDoc(doc(db("coach"), "gameFeeds/p1/feedFollowers/coach"), ask("coach")));
  });

  it("not approved straight away, not as someone else, not from off the team", async () => {
    await assertFails(setDoc(doc(db("coach"), "gameFeeds/p1/feedFollowers/coach"), { ...ask("coach"), status: "approved" }));
    await assertFails(setDoc(doc(db("coach"), "gameFeeds/p1/feedFollowers/family2"), ask("family2")));
    await assertFails(setDoc(doc(db("pend"), "gameFeeds/p1/feedFollowers/pend"), ask("pend")));
    await assertFails(setDoc(doc(db("stranger"), "gameFeeds/p1/feedFollowers/stranger"), ask("stranger")));
  });

  it("the scorer approves, lists and removes; nobody else approves", async () => {
    await put("gameFeeds/p1/feedFollowers/coach", ask("coach"));
    await assertFails(updateDoc(doc(db("coach"), "gameFeeds/p1/feedFollowers/coach"), { status: "approved" }));
    await assertSucceeds(updateDoc(doc(db("family"), "gameFeeds/p1/feedFollowers/coach"), { status: "approved" }));
    await assertSucceeds(getDocs(collection(db("family"), "gameFeeds/p1/feedFollowers")));
    await assertFails(getDocs(collection(db("gran"), "gameFeeds/p1/feedFollowers")));
    await assertSucceeds(deleteDoc(doc(db("family"), "gameFeeds/p1/feedFollowers/coach")));
  });

  it("a follower can leave", async () => {
    await assertSucceeds(deleteDoc(doc(db("gran"), "gameFeeds/p1/feedFollowers/gran")));
  });
});
