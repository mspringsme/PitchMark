// Scan Opponent Lineup (approved 2026-11-06): a parent connected to a
// live room gets the room's opponent roster.
//   1 read the opponent roster
//   2 add opponent roster rows; edit name / jersey / positions / batting side
//   3 never remove (archive) or delete
//   4 never the own team's roster or any other team's
//   5 denied to display devices, id-knowers, other rooms, ended / expired rooms
//   6 new opponent records are the coach's, made only from the coach's room
//   7 rename (name only) records linked from the opponent roster
//   8 lineup links ride the room; only the owner writes the saved game
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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  Timestamp,
  updateDoc,
} from "firebase/firestore";

const LIVE = "live1";
const OTHER_LIVE = "live2";
const GAME = "game1";
const OPP = "oppTeam";
const OWN = "ownTeam";
const OTHER = "otherTeam";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const future = () => Timestamp.fromMillis(Date.now() + 4 * 3600 * 1000);
const past = () => Timestamp.fromMillis(Date.now() - 3600 * 1000);
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

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
  await admin(async (fs) => {
    const put = (path, data) => setDoc(doc(fs, path), data);

    await put(`users/owner/games/${GAME}`, { opponent: "Lions", teamId: OWN, awayTeamId: OPP });
    await put("users/owner/games/game2", { opponent: "Bears", teamId: OWN, awayTeamId: OTHER });

    await put(`liveGames/${LIVE}`, { ownerUid: "owner", status: "active", ownerGameId: GAME, createdAt: Timestamp.fromMillis(1_000), expiresAt: future() });
    await put(`liveGames/${LIVE}/participants/partner`, { uid: "partner" });
    // A parent who isn't a member of either team (H1-H4).
    await put(`liveGames/${LIVE}/participants/parent2`, { uid: "parent2" });
    await put(`liveGames/${LIVE}/displayParticipants/display`, { uid: "display" });
    await put(`liveGames/${OTHER_LIVE}`, { ownerUid: "owner", status: "active", ownerGameId: "game2", expiresAt: future() });
    await put(`liveGames/${OTHER_LIVE}/participants/partner2`, { uid: "partner2" });

    for (const team of [OPP, OWN, OTHER]) {
      await put(`teams/${team}`, { createdByUid: "owner", name: team });
      await put(`teams/${team}/members/owner`, { uid: "owner", roles: ["coach"], addedByUid: "owner" });
    }
    await put(`teams/${OWN}/members/partner`, { uid: "partner", roles: ["parent"], addedByUid: "owner" });

    await put(`teams/${OPP}/players/r1`, {
      name: "Jake Smith", jerseyNumber: "12", createdByUid: "owner",
      pitcherId: "pit1", hitterId: "hit1", playerId: "ply1",
    });
    await put(`teams/${OPP}/players/r2`, {
      name: "Visitor", jerseyNumber: "3", createdByUid: "owner",
      pitcherId: "pitX", hitterId: "hitX", playerId: "plyX",
    });
    await put(`teams/${OWN}/players/k1`, { name: "Our Kid", createdByUid: "owner", pitcherId: "pitOwn", hitterId: "hitOwn", playerId: "plyOwn" });
    await put("hitters/hitOwn", { ownerUid: "owner", name: "Our Kid" });
    await put(`teams/${OTHER}/players/o1`, { name: "Bear", createdByUid: "owner" });

    await put("pitchers/pit1", { ownerUid: "owner", sharedWith: ["owner"], claimedByUid: "owner", name: "Jake Smith" });
    await put("hitters/hit1", { ownerUid: "owner", name: "Jake Smith" });
    await put("players/ply1", { ownerUid: "owner", name: "Jake Smith" });
    // Linked from the opponent roster but someone else's records.
    await put("pitchers/pitX", { ownerUid: "stranger", sharedWith: ["stranger"], name: "Visitor" });
    await put("hitters/hitX", { ownerUid: "stranger", name: "Visitor" });
    await put("players/plyX", { ownerUid: "stranger", name: "Visitor" });
  });
});

const grant = (uid = "partner", liveId = LIVE, team = OPP) =>
  setDoc(doc(db(uid), `teams/${team}/partnerAccess/${uid}`), { uid, liveId, grantedAt: Timestamp.now() });

const seedGrant = (uid = "partner", liveId = LIVE, team = OPP) =>
  admin((fs) => setDoc(doc(fs, `teams/${team}/partnerAccess/${uid}`), { uid, liveId }));

const endRoom = () => admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { status: "ended" }));
const expireRoom = () => admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { expiresAt: past() }));
const leaveRoom = () => admin((fs) => deleteDoc(doc(fs, `liveGames/${LIVE}/participants/partner`)));

const newRow = (extra = {}) => ({ name: "New Kid", jerseyNumber: "77", createdByUid: "partner", ...extra });

describe("the partner's claim (partnerAccess)", () => {
  it("a partner can claim the room's opponent team", async () => {
    await assertSucceeds(grant());
  });

  it("the game's own team too (read only, H1); never a team that isn't in this game", async () => {
    await assertSucceeds(grant("partner", LIVE, OWN));
    await assertFails(grant("partner", LIVE, OTHER));
  });

  it("not through a room they aren't in", async () => {
    await assertFails(grant("partner", OTHER_LIVE, OTHER));
    await assertFails(grant("stranger"));
    await assertFails(grant("display"));
  });

  it("not through an ended or expired room", async () => {
    await endRoom();
    await assertFails(grant());
    await admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { status: "active", expiresAt: past() }));
    await assertFails(grant());
  });

  it("not for someone else, and nothing but the claim", async () => {
    await assertFails(setDoc(doc(db("partner"), `teams/${OPP}/partnerAccess/other`), { uid: "other", liveId: LIVE }));
    await assertFails(setDoc(doc(db("partner"), `teams/${OPP}/partnerAccess/partner`), { uid: "partner", liveId: LIVE, roles: ["coach"] }));
  });
});

describe("rule 1: reading the opponent roster", () => {
  it("a connected partner reads the opponent roster and team", async () => {
    await grant();
    await assertSucceeds(getDocs(collection(db("partner"), `teams/${OPP}/players`)));
    await assertSucceeds(getDoc(doc(db("partner"), `teams/${OPP}/players/r1`)));
    await assertSucceeds(getDoc(doc(db("partner"), `teams/${OPP}`)));
  });

  it("not without the claim", async () => {
    await assertFails(getDocs(collection(db("partner"), `teams/${OPP}/players`)));
  });
});

describe("rules 2-3: adding and editing, never removing", () => {
  it("adds a roster row as themselves", async () => {
    await grant();
    await assertSucceeds(setDoc(doc(db("partner"), `teams/${OPP}/players/n1`), newRow()));
  });

  it("can't add a removed row, or one written as someone else", async () => {
    await grant();
    await assertFails(setDoc(doc(db("partner"), `teams/${OPP}/players/n1`), newRow({ archivedAt: Timestamp.now() })));
    await assertFails(setDoc(doc(db("partner"), `teams/${OPP}/players/n2`), newRow({ createdByUid: "owner" })));
  });

  it("edits name, jersey, positions and batting side", async () => {
    await grant();
    await assertSucceeds(updateDoc(doc(db("partner"), `teams/${OPP}/players/r1`), {
      name: "Jacob Smith", jerseyNumber: "21", positions: ["SS"], battingSide: "left",
    }));
  });

  it("can't remove, delete, or relink a row", async () => {
    await grant();
    await assertFails(updateDoc(doc(db("partner"), `teams/${OPP}/players/r1`), { archivedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(db("partner"), `teams/${OPP}/players/r1`)));
    await assertFails(updateDoc(doc(db("partner"), `teams/${OPP}/players/r1`), { hitterId: "hitX" }));
  });
});

describe("rule 4: never the own team or another team", () => {
  it("a parent on our team still can't write our roster", async () => {
    await grant();
    await assertSucceeds(getDocs(collection(db("partner"), `teams/${OWN}/players`)), "members still read it");
    await assertFails(setDoc(doc(db("partner"), `teams/${OWN}/players/n1`), newRow()));
    await assertFails(updateDoc(doc(db("partner"), `teams/${OWN}/players/k1`), { name: "Renamed" }));
  });

  it("nor another team's", async () => {
    await grant();
    await assertFails(getDocs(collection(db("partner"), `teams/${OTHER}/players`)));
    await assertFails(setDoc(doc(db("partner"), `teams/${OTHER}/players/n1`), newRow()));
  });

  it("the creator keeps full access", async () => {
    await assertSucceeds(updateDoc(doc(db("owner"), `teams/${OPP}/players/r1`), { archivedAt: Timestamp.now() }));
    await assertSucceeds(deleteDoc(doc(db("owner"), `teams/${OPP}/players/r2`)));
  });
});

describe("rule 5: who is denied", () => {
  it("someone who only knows the ids", async () => {
    await assertFails(getDocs(collection(db("stranger"), `teams/${OPP}/players`)));
    await assertFails(setDoc(doc(db("stranger"), `teams/${OPP}/players/n1`), newRow({ createdByUid: "stranger" })));
  });

  it("a claim planted for a room they aren't in", async () => {
    await seedGrant("stranger");
    await assertFails(getDocs(collection(db("stranger"), `teams/${OPP}/players`)));
  });

  it("a display device", async () => {
    await seedGrant("display");
    await assertFails(getDocs(collection(db("display"), `teams/${OPP}/players`)));
  });

  it("a partner from a different room", async () => {
    await seedGrant("partner2", OTHER_LIVE, OPP);
    await assertFails(getDocs(collection(db("partner2"), `teams/${OPP}/players`)));
  });

  it("everyone once the room ends, expires, or they leave it", async () => {
    await grant();
    await endRoom();
    await assertFails(getDocs(collection(db("partner"), `teams/${OPP}/players`)));
    await admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { status: "active" }));
    await assertSucceeds(getDocs(collection(db("partner"), `teams/${OPP}/players`)));
    await expireRoom();
    await assertFails(getDocs(collection(db("partner"), `teams/${OPP}/players`)));
    await admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { expiresAt: future() }));
    await leaveRoom();
    await assertFails(setDoc(doc(db("partner"), `teams/${OPP}/players/n1`), newRow()));
  });

  it("when the game's opponent changes", async () => {
    await grant();
    await admin((fs) => updateDoc(doc(fs, `users/owner/games/${GAME}`), { awayTeamId: OTHER }));
    await assertFails(getDocs(collection(db("partner"), `teams/${OPP}/players`)));
  });
});

describe("rule 6: new opponent records are the coach's", () => {
  const record = (extra = {}) => ({ ownerUid: "owner", createdViaLiveId: LIVE, createdByUid: "partner", name: "New Kid", ...extra });

  it("a partner creates pitcher, hitter and player records owned by the coach", async () => {
    await assertSucceeds(setDoc(doc(db("partner"), "pitchers/new"), record({ sharedWith: ["owner"], claimedByUid: "owner" })));
    await assertSucceeds(setDoc(doc(db("partner"), "hitters/new"), record()));
    await assertSucceeds(setDoc(doc(db("partner"), "players/new"), record()));
  });

  it("not shared with or claimed by the partner", async () => {
    await assertFails(setDoc(doc(db("partner"), "pitchers/new"), record({ sharedWith: ["owner", "partner"] })));
    await assertFails(setDoc(doc(db("partner"), "pitchers/new2"), record({ sharedWith: ["owner"], claimedByUid: "partner" })));
  });

  it("not owned by anyone but the room's owner", async () => {
    await assertFails(setDoc(doc(db("partner"), "hitters/new"), record({ ownerUid: "stranger" })));
  });

  it("not from outside the room, or after it ends", async () => {
    await assertFails(setDoc(doc(db("stranger"), "hitters/new"), record({ createdByUid: "stranger" })));
    await assertFails(setDoc(doc(db("display"), "hitters/new"), record({ createdByUid: "display" })));
    await assertFails(setDoc(doc(db("partner"), "hitters/new"), record({ createdByUid: "owner" })));
    await endRoom();
    await assertFails(setDoc(doc(db("partner"), "players/new"), record()));
  });
});

describe("rule 7: renaming records from the opponent roster", () => {
  const via = (rowId = "r1", teamId = OPP) => ({ teamId, rowId });

  it("a partner renames the records a row links", async () => {
    await grant();
    await assertSucceeds(updateDoc(doc(db("partner"), "pitchers/pit1"), { name: "Jacob Smith", renamedVia: via() }));
    await assertSucceeds(updateDoc(doc(db("partner"), "hitters/hit1"), { name: "Jacob Smith", renamedVia: via() }));
    await assertSucceeds(updateDoc(doc(db("partner"), "players/ply1"), { name: "Jacob Smith", renamedVia: via() }));
  });

  it("name only", async () => {
    await grant();
    await assertFails(updateDoc(doc(db("partner"), "pitchers/pit1"), { name: "J", renamedVia: via(), sharedWith: ["owner", "partner"] }));
    await assertFails(updateDoc(doc(db("partner"), "hitters/hit1"), { ownerUid: "partner", renamedVia: via() }));
  });

  it("not a record the named row doesn't link", async () => {
    await grant();
    await assertFails(updateDoc(doc(db("partner"), "hitters/hit1"), { name: "J", renamedVia: via("r2") }));
  });

  it("not someone else's record, even when the opponent roster links it", async () => {
    await grant();
    await assertFails(updateDoc(doc(db("partner"), "pitchers/pitX"), { name: "J", renamedVia: via("r2") }));
    await assertFails(updateDoc(doc(db("partner"), "hitters/hitX"), { name: "J", renamedVia: via("r2") }));
  });

  it("not without the claim, or after the room ends", async () => {
    await assertFails(updateDoc(doc(db("partner"), "hitters/hit1"), { name: "J", renamedVia: via() }));
    await grant();
    await endRoom();
    await assertFails(updateDoc(doc(db("partner"), "hitters/hit1"), { name: "J", renamedVia: via() }));
  });
});

describe("rule 8: lineup links ride the room", () => {
  it("a partner writes lineup links into the room", async () => {
    await assertSucceeds(updateDoc(doc(db("partner"), `liveGames/${LIVE}`), { hitterIdByBatterId: { cell1: "hit1" } }));
  });

  it("a partner writes field positions into the room, not the saved game (A6)", async () => {
    await assertSucceeds(updateDoc(doc(db("partner"), `liveGames/${LIVE}`), { fieldPositionByBatterId: { cell1: "SS" } }));
    await assertFails(updateDoc(doc(db("partner"), `users/owner/games/${GAME}`), { fieldPositionByBatterId: { cell1: "SS" } }));
    await assertFails(updateDoc(doc(db("display"), `liveGames/${LIVE}`), { fieldPositionByBatterId: { cell1: "SS" } }));
  });

  it("only the owner writes them into the saved game", async () => {
    await assertFails(updateDoc(doc(db("partner"), `users/owner/games/${GAME}`), { hitterIdByBatterId: { cell1: "hit1" } }));
    await assertSucceeds(updateDoc(doc(db("owner"), `users/owner/games/${GAME}`), { hitterIdByBatterId: { cell1: "hit1" } }));
  });
});

describe("H1-H4: the game's own team, read only", () => {
  const own = (uid = "parent2") => grant(uid, LIVE, OWN);

  it("H1 a connected parent reads our roster and team", async () => {
    await own();
    await assertSucceeds(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
    await assertSucceeds(getDoc(doc(db("parent2"), `teams/${OWN}/players/k1`)));
    await assertSucceeds(getDoc(doc(db("parent2"), `teams/${OWN}`)));
  });

  it("H1 not without the claim", async () => {
    await assertFails(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
  });

  it("H2 never adds, edits, removes or deletes our players", async () => {
    await own();
    await assertFails(setDoc(doc(db("parent2"), `teams/${OWN}/players/n1`), newRow({ createdByUid: "parent2" })));
    await assertFails(updateDoc(doc(db("parent2"), `teams/${OWN}/players/k1`), { name: "Renamed" }));
    await assertFails(updateDoc(doc(db("parent2"), `teams/${OWN}/players/k1`), { archivedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(db("parent2"), `teams/${OWN}/players/k1`)));
  });

  it("H2 never renames our players' records", async () => {
    await own();
    await assertFails(updateDoc(doc(db("parent2"), "hitters/hitOwn"), { name: "J", renamedVia: { teamId: OWN, rowId: "k1" } }));
  });

  it("H3 denied to display devices, id-knowers and other rooms", async () => {
    await seedGrant("display", LIVE, OWN);
    await assertFails(getDocs(collection(db("display"), `teams/${OWN}/players`)));
    await seedGrant("stranger", LIVE, OWN);
    await assertFails(getDocs(collection(db("stranger"), `teams/${OWN}/players`)));
    await admin((fs) => updateDoc(doc(fs, "users/owner/games/game2"), { teamId: "elsewhere" }));
    await seedGrant("partner2", OTHER_LIVE, OWN);
    await assertFails(getDocs(collection(db("partner2"), `teams/${OWN}/players`)));
  });

  it("H3 lapses when the room ends or expires, they leave, or the game's team changes", async () => {
    await own();
    await endRoom();
    await assertFails(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
    await admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { status: "active", expiresAt: past() }));
    await assertFails(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
    await admin((fs) => updateDoc(doc(fs, `liveGames/${LIVE}`), { expiresAt: future() }));
    await assertSucceeds(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
    await admin((fs) => updateDoc(doc(fs, `users/owner/games/${GAME}`), { teamId: OTHER }));
    await assertFails(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
    await admin((fs) => updateDoc(doc(fs, `users/owner/games/${GAME}`), { teamId: OWN }));
    await admin((fs) => deleteDoc(doc(fs, `liveGames/${LIVE}/participants/parent2`)));
    await assertFails(getDocs(collection(db("parent2"), `teams/${OWN}/players`)));
  });

  it("H4 opponent add/edit unchanged; an own-team claim opens no writes anywhere", async () => {
    await own();
    await assertFails(setDoc(doc(db("parent2"), `teams/${OPP}/players/n1`), newRow({ createdByUid: "parent2" })),
      "no opponent claim yet");
    await grant("parent2", LIVE, OPP);
    await assertSucceeds(setDoc(doc(db("parent2"), `teams/${OPP}/players/n1`), newRow({ createdByUid: "parent2" })));
    await assertSucceeds(updateDoc(doc(db("parent2"), `teams/${OPP}/players/r1`), { jerseyNumber: "21" }));
    await assertFails(setDoc(doc(db("parent2"), `teams/${OWN}/players/n2`), newRow({ createdByUid: "parent2" })));
  });
});

