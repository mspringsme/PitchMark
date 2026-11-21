// Season Books and Team Sponsors (approved 2026-11-19).
// Season Book:
//   1 only the owner reads or writes their book layouts (users/{uid}/seasonBooks)
//   2 only the owner uploads to bookUploads/{uid}/{orderKey}; images (JPEG/PNG,
//     25 MB max) or the book PDF; nobody else reads or lists them
//   3 the app can't create an order, change its price or mark it paid
// Team Sponsors:
//   4 whoever can see the team reads its slots; anyone signed in can open an
//     active slot by id (shared tourney pages); an expired one only the team
//   5 only the server creates, deletes or re-dates a slot
//   6 the coach who paid edits only name, link and logo, within limits
//
// Expected values come from the approved rules list, not from running the
// rules. Changed after approval, pending the user's OK: the book PDF
// (interior.pdf) may be up to 300 MB - 25 MB can't hold a print-ready book.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { Timestamp, collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";
import { deleteObject, getBytes, listAll, ref, uploadBytes } from "firebase/storage";

const COACH = "coach";
const MEMBER = "member";
const OTHER = "other";
const TEAM = "team_1";
const SLOT = "cs_test_slot";
const KEY = "order-key-0001";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const store = (uid) => env.authenticatedContext(uid).storage();
const anonStore = () => env.unauthenticatedContext().storage();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const adminStore = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.storage()));
const days = (n) => Timestamp.fromMillis(Date.now() + n * 86_400_000);
const slot = (over = {}) => ({
  teamId: TEAM,
  name: "Main St Pizza",
  link: "https://pizza.example",
  logo: "",
  startsAt: days(-10),
  endsAt: days(170),
  purchasedByUid: COACH,
  orderId: SLOT,
  ...over,
});
const pdf = (bytes = 1024) => new Uint8Array(bytes);

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
    await setDoc(doc(f, "teams", TEAM, "members", MEMBER), { uid: MEMBER, roles: ["parent"] });
  });
});

describe("1 book layouts", () => {
  const book = { name: "2026 Spring", pages: [] };

  it("the owner reads and writes their own", async () => {
    await assertSucceeds(setDoc(doc(db(COACH), "users", COACH, "seasonBooks", "b1"), book));
    await assertSucceeds(getDoc(doc(db(COACH), "users", COACH, "seasonBooks", "b1")));
  });

  it("nobody else can read, list or write them", async () => {
    await admin((f) => setDoc(doc(f, "users", COACH, "seasonBooks", "b1"), book));
    await assertFails(getDoc(doc(db(OTHER), "users", COACH, "seasonBooks", "b1")));
    await assertFails(getDocs(collection(db(OTHER), "users", COACH, "seasonBooks")));
    await assertFails(setDoc(doc(db(OTHER), "users", COACH, "seasonBooks", "b2"), book));
  });
});

describe("2 book uploads", () => {
  const path = (uid = COACH, key = KEY, file = "interior.pdf") => `bookUploads/${uid}/${key}/${file}`;

  it("the owner uploads the book PDF and reads it back", async () => {
    await assertSucceeds(uploadBytes(ref(store(COACH), path()), pdf(), { contentType: "application/pdf" }));
    await assertSucceeds(getBytes(ref(store(COACH), path())));
  });

  it("the owner uploads a JPEG or PNG page", async () => {
    await assertSucceeds(uploadBytes(ref(store(COACH), path(COACH, KEY, "page-01.jpg")), pdf(), { contentType: "image/jpeg" }));
    await assertSucceeds(uploadBytes(ref(store(COACH), path(COACH, KEY, "cover.png")), pdf(), { contentType: "image/png" }));
  });

  it("an image over 25 MB is refused", async () => {
    await assertFails(uploadBytes(
      ref(store(COACH), path(COACH, KEY, "big.jpg")),
      new Uint8Array(25 * 1024 * 1024 + 1),
      { contentType: "image/jpeg" }
    ));
  });

  it("other file types and names are refused", async () => {
    await assertFails(uploadBytes(ref(store(COACH), path()), pdf(), { contentType: "text/html" }));
    await assertFails(uploadBytes(ref(store(COACH), path(COACH, KEY, "interior.html")), pdf(), { contentType: "application/pdf" }));
    await assertFails(uploadBytes(ref(store(COACH), path(COACH, KEY, "page.gif")), pdf(), { contentType: "image/gif" }));
    await assertFails(uploadBytes(ref(store(COACH), path(COACH, "short")), pdf(), { contentType: "application/pdf" }));
  });

  it("nobody uploads into someone else's folder", async () => {
    await assertFails(uploadBytes(ref(store(OTHER), path(COACH)), pdf(), { contentType: "application/pdf" }));
    await assertFails(uploadBytes(ref(anonStore(), path(COACH)), pdf(), { contentType: "application/pdf" }));
  });

  it("nobody else reads, lists or deletes the uploads", async () => {
    await adminStore((s) => uploadBytes(ref(s, path()), pdf(), { contentType: "application/pdf" }));
    await assertFails(getBytes(ref(store(OTHER), path())));
    await assertFails(getBytes(ref(anonStore(), path())));
    await assertFails(listAll(ref(store(OTHER), `bookUploads/${COACH}/${KEY}`)));
    await assertFails(deleteObject(ref(store(OTHER), path())));
  });

  it("nothing else in the bucket is readable or writable", async () => {
    await assertFails(uploadBytes(ref(store(COACH), `moments/${COACH}/clip.jpg`), pdf(), { contentType: "image/jpeg" }));
    await assertFails(getBytes(ref(store(COACH), `moments/${COACH}/clip.jpg`)));
  });
});

describe("3 orders are server-only", () => {
  it("the app can't create an order", async () => {
    await assertFails(setDoc(doc(db(COACH), "retailOrders", "cs_fake"), {
      firebaseUid: COACH, itemKind: "seasonBook", paymentStatus: "paid", amountTotal: 1,
    }));
  });

  it("the app can't change an order's price, payment or print state", async () => {
    await admin((f) => setDoc(doc(f, "retailOrders", "cs_1"), {
      firebaseUid: COACH, itemKind: "seasonBook", paymentStatus: "unpaid", amountTotal: 4900,
    }));
    await assertSucceeds(getDoc(doc(db(COACH), "retailOrders", "cs_1")));
    await assertFails(updateDoc(doc(db(COACH), "retailOrders", "cs_1"), { paymentStatus: "paid" }));
    await assertFails(updateDoc(doc(db(COACH), "retailOrders", "cs_1"), { amountTotal: 1 }));
    await assertFails(updateDoc(doc(db(COACH), "retailOrders", "cs_1"), { printSubmission: null }));
  });
});

describe("4 reading sponsor slots", () => {
  beforeEach(() => admin(async (f) => {
    await setDoc(doc(f, "teams", TEAM, "sponsors", SLOT), slot());
    await setDoc(doc(f, "teams", TEAM, "sponsors", "old"), slot({ endsAt: days(-1), orderId: "old" }));
  }));

  it("the coach and team members read and list them, expired ones too", async () => {
    for (const uid of [COACH, MEMBER]) {
      await assertSucceeds(getDoc(doc(db(uid), "teams", TEAM, "sponsors", SLOT)));
      await assertSucceeds(getDoc(doc(db(uid), "teams", TEAM, "sponsors", "old")));
      await assertSucceeds(getDocs(collection(db(uid), "teams", TEAM, "sponsors")));
    }
  });

  it("anyone signed in opens an active slot by id, never an expired one or the list", async () => {
    await assertSucceeds(getDoc(doc(db(OTHER), "teams", TEAM, "sponsors", SLOT)));
    await assertFails(getDoc(doc(db(OTHER), "teams", TEAM, "sponsors", "old")));
    await assertFails(getDocs(collection(db(OTHER), "teams", TEAM, "sponsors")));
  });

  it("signed out can't read them", async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "teams", TEAM, "sponsors", SLOT)));
  });
});

describe("5 only the server makes, removes or re-dates a slot", () => {
  it("nobody creates one, not even the coach", async () => {
    await assertFails(setDoc(doc(db(COACH), "teams", TEAM, "sponsors", "free"), slot({ orderId: "free" })));
  });

  it("nobody deletes one or changes its dates, team or payer", async () => {
    await admin((f) => setDoc(doc(f, "teams", TEAM, "sponsors", SLOT), slot()));
    const r = doc(db(COACH), "teams", TEAM, "sponsors", SLOT);
    await assertFails(deleteDoc(r));
    await assertFails(updateDoc(r, { endsAt: days(900) }));
    await assertFails(updateDoc(r, { startsAt: days(-400) }));
    await assertFails(updateDoc(r, { teamId: "team_2" }));
    await assertFails(updateDoc(r, { purchasedByUid: OTHER }));
    await assertFails(updateDoc(r, { playerNames: ["Ava"] }));
  });
});

describe("6 the paying coach edits the sponsor's name, link and logo", () => {
  beforeEach(() => admin((f) => setDoc(doc(f, "teams", TEAM, "sponsors", SLOT), slot())));
  const r = (uid) => doc(db(uid), "teams", TEAM, "sponsors", SLOT);

  it("the coach who paid can", async () => {
    await assertSucceeds(updateDoc(r(COACH), { name: "Main Street Pizza", link: "", logo: "AAAA" }));
  });

  it("within limits: name 1-60, https link up to 200, logo up to 100,000", async () => {
    await assertFails(updateDoc(r(COACH), { name: "" }));
    await assertFails(updateDoc(r(COACH), { name: "x".repeat(61) }));
    await assertFails(updateDoc(r(COACH), { link: "http://pizza.example" }));
    await assertFails(updateDoc(r(COACH), { link: "https://" + "x".repeat(200) }));
    await assertFails(updateDoc(r(COACH), { logo: "A".repeat(100001) }));
    await assertFails(updateDoc(r(COACH), { name: 42 }));
  });

  it("a team member or anyone else can't", async () => {
    await assertFails(updateDoc(r(MEMBER), { name: "Hijacked" }));
    await assertFails(updateDoc(r(OTHER), { name: "Hijacked" }));
  });

  it("a coach who didn't pay for this slot can't", async () => {
    await admin((f) => setDoc(doc(f, "teams", TEAM, "sponsors", SLOT), slot({ purchasedByUid: "formerCoach" })));
    await assertFails(updateDoc(r(COACH), { name: "Mine now" }));
  });
});
