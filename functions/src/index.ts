import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import crypto from "crypto";

admin.initializeApp();

const otpSecret = defineSecret("OTP_SECRET");
const resendApiKey = defineSecret("RESEND_API_KEY");

interface PitchCall {
  pitch: string;
  location: string;
  isStrike: boolean;
}

interface PitchEvent {
  timestamp: admin.firestore.Timestamp;
  pitch: string;
  location: string;
  isStrike: boolean;
  isBall?: boolean;
  mode: "game" | "practice";
  calledPitch?: PitchCall | null;
  batterSide: "left" | "right";
  strikeSwinging: boolean;
  strikeLooking: boolean;
  wildPitch: boolean;
  passedBall: boolean;
  outcome?: string | null;
  opponentJersey?: string | null;
  gameId?: string | null;
  practiceId?: string | null;
  pitcherId?: string | null;
}

interface PitcherStatsDoc {
  pitcherId: string;
  scope: "overall" | "game" | "practice";
  scopeId: string;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  totalCount: number;
  strikeCount: number;
  ballCount: number;
  swingingStrikeCount: number;
  lookingStrikeCount: number;
  wildPitchCount: number;
  passedBallCount: number;
  walkCount: number;
  hitSpotCount: number;
  pitchStats: Record<string, { count: number; hitSpotCount: number }>;
  outcomeStats: Record<string, { count: number; jerseys: string[] }>;
  pitchLocationStats: Record<string, { count: number; hitCount: number; missCount: number; jerseys: string[] }>;
}

function normalizePitch(raw: string): string {
  return (raw || "").trim().toLowerCase();
}

function swapInOut(raw: string): string {
  let output = raw;
  const replaceWholeWord = (word: string, replacement: string) => {
    if (output === word) output = replacement;
    output = output.replace(new RegExp(`\\b${word}\\b`, "g"), replacement);
    output = output.replace(new RegExp(`&\\s+${word}\\b`, "g"), `& ${replacement}`);
    output = output.replace(new RegExp(`\\b${word}\\s+&`, "g"), `${replacement} &`);
  };

  replaceWholeWord("In", "__TEMP_IN__");
  replaceWholeWord("Out", "In");
  replaceWholeWord("__TEMP_IN__", "Out");
  return output;
}

function normalizeLocation(raw: string, batterSide: "left" | "right"): { type: string | null; zone: string } {
  let adjusted = raw || "";
  if (batterSide === "left") {
    adjusted = swapInOut(adjusted);
  }

  const cleaned = adjusted
    .replace(/—/g, " ")
    .replace(/–/g, " ")
    .replace(/-/g, " ")
    .replace(/&/g, "and")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();

  if (cleaned.startsWith("strike ")) {
    return { type: "strike", zone: cleaned.substring("strike ".length).trim() };
  }
  if (cleaned.startsWith("ball ")) {
    return { type: "ball", zone: cleaned.substring("ball ".length).trim() };
  }
  return { type: null, zone: cleaned };
}

function strictIsLocationMatch(event: PitchEvent): boolean {
  if (!event.calledPitch) return false;
  const called = event.calledPitch;

  const calledPitchNorm = normalizePitch(called.pitch);
  const actualPitchNorm = normalizePitch(event.pitch);
  if (calledPitchNorm !== actualPitchNorm) return false;

  const calledLoc = normalizeLocation(called.location, event.batterSide);
  const actualLoc = normalizeLocation(event.location, event.batterSide);

  if (calledLoc.zone !== actualLoc.zone) return false;

  if (calledLoc.type && actualLoc.type) {
    return calledLoc.type === actualLoc.type;
  }
  if (calledLoc.type && !actualLoc.type) {
    const actualType = event.isStrike ? "strike" : "ball";
    return calledLoc.type === actualType;
  }
  if (!calledLoc.type && actualLoc.type) {
    const calledType = called.isStrike ? "strike" : "ball";
    return calledType === actualLoc.type;
  }
  return true;
}

function resultType(event: PitchEvent): "strike" | "ball" | null {
  const raw = (event.location || "").trim().toLowerCase();
  if (raw.startsWith("strike ")) return "strike";
  if (raw.startsWith("ball ")) return "ball";
  return null;
}

function defaultStats(pitcherId: string, scope: "overall" | "game" | "practice", scopeId: string): PitcherStatsDoc {
  return {
    pitcherId,
    scope,
    scopeId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    totalCount: 0,
    strikeCount: 0,
    ballCount: 0,
    swingingStrikeCount: 0,
    lookingStrikeCount: 0,
    wildPitchCount: 0,
    passedBallCount: 0,
    walkCount: 0,
    hitSpotCount: 0,
    pitchStats: {},
    outcomeStats: {},
    pitchLocationStats: {}
  };
}

function applyEvent(stats: PitcherStatsDoc, event: PitchEvent): PitcherStatsDoc {
  const updated: PitcherStatsDoc = { ...stats };
  updated.updatedAt = admin.firestore.FieldValue.serverTimestamp();

  updated.totalCount += 1;

  const type = resultType(event);
  if (type === "strike") updated.strikeCount += 1;
  if (type === "ball") updated.ballCount += 1;

  if (event.strikeSwinging && event.outcome === "K") updated.swingingStrikeCount += 1;
  if (event.strikeLooking && event.outcome === "ꓘ") updated.lookingStrikeCount += 1;
  if (event.wildPitch) updated.wildPitchCount += 1;
  if (event.passedBall) updated.passedBallCount += 1;

  const outcome = (event.outcome || "").trim();
  if (outcome === "BB" || outcome === "Walk") updated.walkCount += 1;

  const hitSpot = strictIsLocationMatch(event);
  if (hitSpot) updated.hitSpotCount += 1;

  const pitchKey = (event.pitch || "Unknown Pitch").trim() || "Unknown Pitch";
  if (!updated.pitchStats[pitchKey]) {
    updated.pitchStats[pitchKey] = { count: 0, hitSpotCount: 0 };
  }
  updated.pitchStats[pitchKey].count += 1;
  if (hitSpot) updated.pitchStats[pitchKey].hitSpotCount += 1;

  if (outcome) {
    if (!updated.outcomeStats[outcome]) {
      updated.outcomeStats[outcome] = { count: 0, jerseys: [] };
    }
    updated.outcomeStats[outcome].count += 1;
    const jersey = (event.opponentJersey || "").trim();
    if (jersey && !updated.outcomeStats[outcome].jerseys.includes(jersey)) {
      updated.outcomeStats[outcome].jerseys.push(jersey);
    }
  }

  const safePitch = (event.pitch || "Unknown Pitch").trim() || "Unknown Pitch";
  const safeLocation = (event.location || "Unknown Location").trim() || "Unknown Location";
  const locKey = `${safePitch}||${safeLocation}`;
  if (!updated.pitchLocationStats[locKey]) {
    updated.pitchLocationStats[locKey] = { count: 0, hitCount: 0, missCount: 0, jerseys: [] };
  }
  updated.pitchLocationStats[locKey].count += 1;
  if (hitSpot) updated.pitchLocationStats[locKey].hitCount += 1;
  else updated.pitchLocationStats[locKey].missCount += 1;

  const jersey = (event.opponentJersey || "").trim();
  if (jersey && !updated.pitchLocationStats[locKey].jerseys.includes(jersey)) {
    updated.pitchLocationStats[locKey].jerseys.push(jersey);
  }

  return updated;
}

async function updateStatsDoc(
  pitcherId: string,
  scope: "overall" | "game" | "practice",
  scopeId: string,
  event: PitchEvent
): Promise<void> {
  const db = admin.firestore();
  const docId = scope === "overall" ? "overall" : `${scope}_${scopeId}`;
  const ref = db.collection("pitchers").doc(pitcherId).collection("stats").doc(docId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const base = snap.exists
      ? (snap.data() as PitcherStatsDoc)
      : defaultStats(pitcherId, scope, scopeId);
    const updated = applyEvent({ ...base }, event);
    tx.set(ref, updated, { merge: false });
  });
}

exports.onPitcherPitchEventCreate = functions.firestore
  .document("pitchers/{pitcherId}/pitchEvents/{eventId}")
  .onCreate(async (
    snap: functions.firestore.DocumentSnapshot,
    context: functions.EventContext
  ) => {
    const pitcherId = context.params.pitcherId as string;
    const event = snap.data() as PitchEvent;

    if (!pitcherId || !event) return;

    const updates: Promise<void>[] = [];

    updates.push(updateStatsDoc(pitcherId, "overall", "overall", event));

    if (event.gameId) {
      updates.push(updateStatsDoc(pitcherId, "game", event.gameId, event));
    }

    const practiceId = (event.practiceId || "").trim();
    if (event.mode === "practice") {
      updates.push(updateStatsDoc(pitcherId, "practice", practiceId || "__GENERAL__", event));
    }

    await Promise.all(updates);
  });

const OTP_TTL_MINUTES = 10;
const OTP_ATTEMPT_LIMIT = 3;

function requireString(input: unknown, field: string): string {
  if (typeof input !== "string") {
    throw new functions.https.HttpsError("invalid-argument", `${field} must be a string`);
  }
  const trimmed = input.trim().toLowerCase();
  if (!trimmed) {
    throw new functions.https.HttpsError("invalid-argument", `${field} is required`);
  }
  return trimmed;
}

function getOtpSecret(): string {
  const secret = otpSecret.value() || process.env.OTP_SECRET;
  if (!secret) {
    throw new functions.https.HttpsError("failed-precondition", "OTP secret not configured");
  }
  return secret;
}

function hashOtp(email: string, code: string): string {
  const secret = getOtpSecret();
  return crypto.createHash("sha256").update(`${secret}:${email}:${code}`).digest("hex");
}

function generateOtp(): string {
  const value = Math.floor(100000 + Math.random() * 900000);
  return String(value);
}

async function sendOtpEmail(email: string, code: string): Promise<void> {
  const resendKey = resendApiKey.value() || process.env.RESEND_API_KEY;
  if (!resendKey) {
    throw new functions.https.HttpsError("failed-precondition", "Resend API key not configured");
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      from: "PitchMark <no-reply@mail.pitchmarkcode.com>",
      to: [email],
      subject: "Your PitchMark sign-in code",
      html: `<p>Your PitchMark sign-in code is <strong>${code}</strong>.</p><p>This code expires in ${OTP_TTL_MINUTES} minutes.</p>`,
      text: `Your PitchMark sign-in code is ${code}. It expires in ${OTP_TTL_MINUTES} minutes.`
    })
  });

  if (!response.ok) {
    const body = await response.text();
    throw new functions.https.HttpsError(
      "internal",
      `Failed to send OTP email: ${response.status} ${body}`
    );
  }
}

const DELETE_BATCH_SIZE = 400;

async function deleteQueryBatch(
  db: admin.firestore.Firestore,
  query: admin.firestore.Query
): Promise<void> {
  const snapshot = await query.limit(DELETE_BATCH_SIZE).get();
  if (snapshot.empty) return;

  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  if (snapshot.size === DELETE_BATCH_SIZE) {
    await deleteQueryBatch(db, query);
  }
}

async function deleteSubcollection(
  db: admin.firestore.Firestore,
  docRef: admin.firestore.DocumentReference,
  subcollection: string
): Promise<void> {
  await deleteQueryBatch(db, docRef.collection(subcollection));
}

exports.requestEmailOtp = functions
  .runWith({ secrets: [otpSecret, resendApiKey] })
  .https.onCall(async (data: { email?: string }) => {
  const email = requireString(data?.email, "email");
  const code = generateOtp();
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000)
  );

  const ref = db.collection("otpRequests").doc(email);
  await ref.set(
    {
      email,
      codeHash: hashOtp(email, code),
      createdAt: now,
      expiresAt,
      attemptsRemaining: OTP_ATTEMPT_LIMIT
    },
    { merge: false }
  );

  await sendOtpEmail(email, code);
  return { status: "sent" };
  });

exports.verifyEmailOtp = functions
  .runWith({ secrets: [otpSecret] })
  .https.onCall(async (data: { email?: string; code?: string }) => {
  const email = requireString(data?.email, "email");
  const code = requireString(data?.code, "code");

  const db = admin.firestore();
  const ref = db.collection("otpRequests").doc(email);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "No OTP request found");
    }
    const payload = snap.data() as {
      codeHash: string;
      expiresAt: admin.firestore.Timestamp;
      attemptsRemaining: number;
    };

    if (payload.expiresAt.toMillis() < Date.now()) {
      tx.delete(ref);
      throw new functions.https.HttpsError("deadline-exceeded", "OTP expired");
    }

    if (payload.attemptsRemaining <= 0) {
      tx.delete(ref);
      throw new functions.https.HttpsError("resource-exhausted", "OTP attempts exceeded");
    }

    const matches = payload.codeHash === hashOtp(email, code);
    if (!matches) {
      tx.update(ref, { attemptsRemaining: payload.attemptsRemaining - 1 });
      throw new functions.https.HttpsError("permission-denied", "Invalid OTP code");
    }

    tx.delete(ref);
    return true;
  });

  if (!result) {
    throw new functions.https.HttpsError("internal", "OTP verification failed");
  }

  let userRecord: admin.auth.UserRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (error: unknown) {
    userRecord = await admin.auth().createUser({ email });
  }

  const customToken = await admin.auth().createCustomToken(userRecord.uid);
  return { token: customToken };
  });

exports.deleteAccount = functions.https.onCall(async (_, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Not signed in.");
  }

  const authTime = context.auth.token.auth_time || 0;
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (nowSeconds - authTime > 5 * 60) {
    throw new functions.https.HttpsError("unauthenticated", "Recent login required.");
  }

  const uid = context.auth.uid;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);

  const userRecord = await admin.auth().getUser(uid);
  const userEmail = userRecord.email || null;

  // user-scoped subcollections
  await deleteQueryBatch(db, userRef.collection("templates"));
  await deleteQueryBatch(db, userRef.collection("pitchEvents"));

  const gamesSnap = await userRef.collection("games").get();
  for (const gameDoc of gamesSnap.docs) {
    await deleteSubcollection(db, gameDoc.ref, "pitchEvents");
    await gameDoc.ref.delete();
  }

  // shared templates (owner) + shared with arrays cleanup
  const ownedTemplatesSnap = await db.collection("templates").where("ownerUid", "==", uid).get();
  for (const doc of ownedTemplatesSnap.docs) {
    await doc.ref.delete();
  }

  const sharedTemplatesSnap = await db.collection("templates").where("sharedWith", "array-contains", uid).get();
  for (const doc of sharedTemplatesSnap.docs) {
    const updates: Record<string, admin.firestore.FieldValue> = {
      sharedWith: admin.firestore.FieldValue.arrayRemove(uid)
    };
    if (userEmail) {
      updates.sharedWithEmails = admin.firestore.FieldValue.arrayRemove(userEmail);
    }
    await doc.ref.update(updates);
  }

  // pitchers (owner) + shared with arrays cleanup
  const ownedPitchersSnap = await db.collection("pitchers").where("ownerUid", "==", uid).get();
  for (const doc of ownedPitchersSnap.docs) {
    await deleteSubcollection(db, doc.ref, "pitchEvents");
    await deleteSubcollection(db, doc.ref, "stats");
    await doc.ref.delete();
  }

  const sharedPitchersSnap = await db.collection("pitchers").where("sharedWith", "array-contains", uid).get();
  for (const doc of sharedPitchersSnap.docs) {
    await doc.ref.update({
      sharedWith: admin.firestore.FieldValue.arrayRemove(uid)
    });
  }

  // live games owned by user
  const liveGamesSnap = await db.collection("liveGames").where("ownerUid", "==", uid).get();
  for (const doc of liveGamesSnap.docs) {
    await deleteSubcollection(db, doc.ref, "participants");
    await deleteSubcollection(db, doc.ref, "pitchEvents");
    await doc.ref.delete();
  }

  // join/invite tokens owned by user
  await deleteQueryBatch(db, db.collection("joinCodes").where("ownerUid", "==", uid));
  await deleteQueryBatch(db, db.collection("inviteTokens").where("ownerUid", "==", uid));
  await deleteQueryBatch(db, db.collection("pitcherInviteTokens").where("ownerUid", "==", uid));

  // remove OTP request keyed by email if present
  if (userEmail) {
    await db.collection("otpRequests").doc(userEmail).delete().catch(() => {});
  }

  await userRef.delete().catch(() => {});
  await admin.auth().deleteUser(uid);

  return { status: "deleted" };
});
