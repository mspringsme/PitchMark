import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

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
  .onCreate(async (snap, context) => {
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
