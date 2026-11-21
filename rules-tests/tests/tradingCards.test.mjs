// Trading card team sets (approved 2026-11-19):
//   R1 only the coach or a team member starts a set; the starter is the
//      organizer and nobody can change that
//   R2 only the coach and team members read the set and its entries
//   R3 a family writes only entries it owns (ownerUid; one per card, so
//      siblings each get one), only while open, and can withdraw them while
//      open; the organizer can remove any entry while open
//      (revised 2026-11-20 at the user's request: was one entry per account)
//   R4 an entry records consent (with a time); only allow-listed fields
//   R5 only the organizer locks; after locking no entry changes; only the
//      server marks a set ordered
//   R6 card art cardArt/{team}/{set}/{uid}/{entryId}-front|back: only that family uploads
//      (JPEG/PNG, 10 MB), only while open; only the team reads it; nothing
//      else (cardOrders/) opens
//   R7 a family's own card designs (users/{uid}/cardDesigns) are owner-only
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
import { Timestamp, collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";
import { deleteObject, getBytes, ref, uploadBytes } from "firebase/storage";

const COACH = "coach";
const PARENT = "parent";
const PARENT2 = "parent2";
const OUTSIDER = "outsider";
const TEAM = "team_1";
const SET = "set_1";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const store = (uid) => env.authenticatedContext(uid).storage();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const adminStore = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.storage()));
const setRef = (uid, id = SET) => doc(db(uid), "teams", TEAM, "cardSets", id);
const entryRef = (uid, entryId) => doc(db(uid), "teams", TEAM, "cardSets", SET, "entries", entryId);
const artPath = (uid, entryId = "card1", side = "front", ext = "png") => `cardArt/${TEAM}/${SET}/${uid}/${entryId}-${side}.${ext}`;
const img = (bytes = 512) => new Uint8Array(bytes);

const newSet = (organizerUid) => ({ organizerUid, status: "open", name: "2026 Spring Cards", createdAt: Timestamp.now() });
const entry = (uid, entryId = "card1", over = {}) => ({
  ownerUid: uid,
  playerName: "Ava Smith",
  jerseyNumber: "12",
  templateId: "classic",
  frontPath: artPath(uid, entryId, "front"),
  backPath: artPath(uid, entryId, "back"),
  consent: true,
  consentedAt: Timestamp.now(),
  updatedAt: Timestamp.now(),
  ...over,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-pitchmark-rules",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8085,
    },
    storage: {
      rules: readFileSync(new URL("../../storage.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await admin(async (f) => {
    await setDoc(doc(f, "teams", TEAM), { createdByUid: COACH, name: "Lightning" });
    await setDoc(doc(f, "teams", TEAM, "members", PARENT), { uid: PARENT, roles: ["parent"] });
    await setDoc(doc(f, "teams", TEAM, "members", PARENT2), { uid: PARENT2, roles: ["parent"] });
  });
});

const seedSet = (over = {}) => admin((f) => setDoc(doc(f, "teams", TEAM, "cardSets", SET), { ...newSet(PARENT), ...over }));

describe("R1 starting a set", () => {
  it("the coach or a team member starts one, as its organizer", async () => {
    await assertSucceeds(setDoc(setRef(COACH, "s_coach"), newSet(COACH)));
    await assertSucceeds(setDoc(setRef(PARENT, "s_parent"), newSet(PARENT)));
  });

  it("an outsider can't, and nobody starts one naming someone else", async () => {
    await assertFails(setDoc(setRef(OUTSIDER, "s_x"), newSet(OUTSIDER)));
    await assertFails(setDoc(setRef(PARENT, "s_y"), newSet(PARENT2)));
  });

  it("a set starts open, with no extra fields", async () => {
    await assertFails(setDoc(setRef(PARENT, "s_z"), { ...newSet(PARENT), status: "locked" }));
    await assertFails(setDoc(setRef(PARENT, "s_z"), { ...newSet(PARENT), status: "ordered" }));
    await assertFails(setDoc(setRef(PARENT, "s_z"), { ...newSet(PARENT), orderId: "free" }));
  });

  it("nobody changes the organizer", async () => {
    await seedSet();
    await assertFails(updateDoc(setRef(PARENT), { organizerUid: PARENT2 }));
    await assertFails(updateDoc(setRef(COACH), { organizerUid: COACH }));
  });
});

describe("R2 who can see a set", () => {
  beforeEach(async () => {
    await seedSet();
    await admin((f) => setDoc(doc(f, "teams", TEAM, "cardSets", SET, "entries", "card1"), entry(PARENT2)));
  });

  it("the coach and members read the set and its entries", async () => {
    for (const uid of [COACH, PARENT, PARENT2]) {
      await assertSucceeds(getDoc(setRef(uid)));
      await assertSucceeds(getDocs(collection(db(uid), "teams", TEAM, "cardSets")));
      await assertSucceeds(getDocs(collection(db(uid), "teams", TEAM, "cardSets", SET, "entries")));
    }
  });

  it("an outsider reads nothing", async () => {
    await assertFails(getDoc(setRef(OUTSIDER)));
    await assertFails(getDocs(collection(db(OUTSIDER), "teams", TEAM, "cardSets")));
    await assertFails(getDoc(entryRef(OUTSIDER, "card1")));
  });
});

describe("R3 entries while open", () => {
  beforeEach(() => seedSet());

  it("a family writes and withdraws its own entry", async () => {
    await assertSucceeds(setDoc(entryRef(PARENT2, "ava"), entry(PARENT2, "ava")));
    await assertSucceeds(updateDoc(entryRef(PARENT2, "ava"), { playerName: "Ava S.", updatedAt: Timestamp.now() }));
    await assertSucceeds(deleteDoc(entryRef(PARENT2, "ava")));
  });

  it("siblings: one family adds a card for each of its players", async () => {
    await assertSucceeds(setDoc(entryRef(PARENT2, "ava"), entry(PARENT2, "ava")));
    await assertSucceeds(setDoc(entryRef(PARENT2, "bea"), entry(PARENT2, "bea", { playerName: "Bea Smith", jerseyNumber: "4" })));
    const all = await getDocs(collection(db(PARENT2), "teams", TEAM, "cardSets", SET, "entries"));
    if (all.size !== 2) throw new Error(`expected 2 entries, found ${all.size}`);
  });

  it("nobody writes, takes over or removes another family's entry", async () => {
    await assertFails(setDoc(entryRef(PARENT, "x"), entry(PARENT2, "x")));
    await assertFails(setDoc(entryRef(OUTSIDER, "y"), entry(OUTSIDER, "y")));
    await admin((f) => setDoc(doc(f, "teams", TEAM, "cardSets", SET, "entries", "ava"), entry(PARENT2, "ava")));
    await assertFails(setDoc(entryRef(COACH, "ava"), entry(COACH, "ava")));
    await assertFails(updateDoc(entryRef(COACH, "ava"), { playerName: "Mine now" }));
    await assertFails(deleteDoc(entryRef(COACH, "ava")));
  });

  it("the organizer can remove any entry", async () => {
    await admin((f) => setDoc(doc(f, "teams", TEAM, "cardSets", SET, "entries", "ava"), entry(PARENT2, "ava")));
    await assertSucceeds(deleteDoc(entryRef(PARENT, "ava")));
  });
});

describe("R4 consent and fields", () => {
  beforeEach(() => seedSet());

  it("an entry without consent is refused", async () => {
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { consent: false })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { consent: "yes" })));
    const { consentedAt, ...noTime } = entry(PARENT2, "c");
    await assertFails(setDoc(entryRef(PARENT2, "c"), noTime));
  });

  it("only allow-listed fields, and art only from the family's own folder and card", async () => {
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { birthdate: "2016-04-01" })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { school: "Lincoln Elementary" })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { frontPath: artPath(PARENT, "c", "front") })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { frontPath: artPath(PARENT2, "other", "front") })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { backPath: `cardArt/${TEAM}/other/${PARENT2}/c-back.png` })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { playerName: "" })));
    await assertFails(setDoc(entryRef(PARENT2, "c"), entry(PARENT2, "c", { ownerUid: PARENT })));
  });
});

describe("R5 locking", () => {
  it("only the organizer locks and reopens", async () => {
    await seedSet();
    await assertFails(updateDoc(setRef(PARENT2), { status: "locked" }));
    await assertFails(updateDoc(setRef(COACH), { status: "locked" }));
    await assertSucceeds(updateDoc(setRef(PARENT), { status: "locked", lockedAt: Timestamp.now() }));
    await assertSucceeds(updateDoc(setRef(PARENT), { status: "open" }));
  });

  it("after locking no entry is written, changed or removed", async () => {
    await seedSet({ status: "locked" });
    await admin((f) => setDoc(doc(f, "teams", TEAM, "cardSets", SET, "entries", "ava"), entry(PARENT2, "ava")));
    await assertFails(setDoc(entryRef(COACH, "new"), entry(COACH, "new")));
    await assertFails(updateDoc(entryRef(PARENT2, "ava"), { playerName: "Changed" }));
    await assertFails(deleteDoc(entryRef(PARENT2, "ava")));
    await assertFails(deleteDoc(entryRef(PARENT, "ava")));
  });

  it("only the server marks a set ordered, and an ordered set is final", async () => {
    await seedSet({ status: "locked" });
    await assertFails(updateDoc(setRef(PARENT), { status: "ordered" }));
    await seedSet({ status: "ordered" });
    await assertFails(updateDoc(setRef(PARENT), { status: "open" }));
    await assertFails(updateDoc(setRef(PARENT), { name: "Renamed" }));
  });

  it("nobody deletes a set", async () => {
    await seedSet();
    await assertFails(deleteDoc(setRef(PARENT)));
  });
});

describe("R6 card art", () => {
  it("a family uploads its own two sides while the set is open", async () => {
    await seedSet();
    await assertSucceeds(uploadBytes(ref(store(PARENT2), artPath(PARENT2, "card1", "front")), img(), { contentType: "image/png" }));
    await assertSucceeds(uploadBytes(ref(store(PARENT2), artPath(PARENT2, "card1", "back", "jpg")), img(), { contentType: "image/jpeg" }));
    // A sibling's card, same family folder.
    await assertSucceeds(uploadBytes(ref(store(PARENT2), artPath(PARENT2, "card2", "front")), img(), { contentType: "image/png" }));
  });

  it("not into another family's folder, not as an outsider, not other files", async () => {
    await seedSet();
    await assertFails(uploadBytes(ref(store(PARENT), artPath(PARENT2)), img(), { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(store(OUTSIDER), artPath(OUTSIDER)), img(), { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(store(PARENT2), `cardArt/${TEAM}/${SET}/${PARENT2}/photo.png`), img(), { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(store(PARENT2), artPath(PARENT2)), img(), { contentType: "application/pdf" }));
  });

  it("over 10 MB is refused", async () => {
    await seedSet();
    await assertFails(uploadBytes(ref(store(PARENT2), artPath(PARENT2)), new Uint8Array(10 * 1024 * 1024 + 1), { contentType: "image/png" }));
  });

  it("nothing is uploaded or removed once the set is locked", async () => {
    await seedSet();
    await adminStore((s) => uploadBytes(ref(s, artPath(PARENT2)), img(), { contentType: "image/png" }));
    await admin((f) => updateDoc(doc(f, "teams", TEAM, "cardSets", SET), { status: "locked" }));
    await assertFails(uploadBytes(ref(store(PARENT2), artPath(PARENT2)), img(), { contentType: "image/png" }));
    await assertFails(deleteObject(ref(store(PARENT2), artPath(PARENT2))));
  });

  it("the team sees every card; an outsider sees none", async () => {
    await seedSet();
    await adminStore((s) => uploadBytes(ref(s, artPath(PARENT2)), img(), { contentType: "image/png" }));
    await assertSucceeds(getBytes(ref(store(COACH), artPath(PARENT2))));
    await assertSucceeds(getBytes(ref(store(PARENT), artPath(PARENT2))));
    await assertFails(getBytes(ref(store(OUTSIDER), artPath(PARENT2))));
  });

  it("a paid order's frozen art (cardOrders/) is server-only", async () => {
    await adminStore((s) => uploadBytes(ref(s, "cardOrders/order-key-0001/parent2-front.png"), img(), { contentType: "image/png" }));
    await assertFails(getBytes(ref(store(PARENT), "cardOrders/order-key-0001/parent2-front.png")));
    await assertFails(uploadBytes(ref(store(PARENT), "cardOrders/order-key-0001/parent-front.png"), img(), { contentType: "image/png" }));
  });
});

describe("R7 a family's own designs", () => {
  const design = { playerName: "Ava", templateId: "classic" };

  it("the owner reads and writes their own", async () => {
    await assertSucceeds(setDoc(doc(db(PARENT), "users", PARENT, "cardDesigns", "d1"), design));
    await assertSucceeds(getDoc(doc(db(PARENT), "users", PARENT, "cardDesigns", "d1")));
  });

  it("nobody else, not even the coach", async () => {
    await admin((f) => setDoc(doc(f, "users", PARENT, "cardDesigns", "d1"), design));
    await assertFails(getDoc(doc(db(COACH), "users", PARENT, "cardDesigns", "d1")));
    await assertFails(getDocs(collection(db(PARENT2), "users", PARENT, "cardDesigns")));
    await assertFails(setDoc(doc(db(COACH), "users", PARENT, "cardDesigns", "d2"), design));
  });
});
