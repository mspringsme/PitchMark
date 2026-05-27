# PitchMark Submission Readiness Checklist

Release target: ____________________
Build number: ____________________
Owner: ____________________
Last updated: ____________________

Status key:
- [ ] Not started
- [~] In progress
- [x] Done
- [!] Blocked

## 1) Revenue-Critical Subscription Validation

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [x] | New purchase unlock | `isPro` flips to `true` immediately after verified purchase in StoreKit config and Sandbox |  | 
• “Launch entitlement restore passed in local StoreKit run: is​Pro false -> true on init.”
• “App Check 403 present in logs; unresolved.”
• “StoreKit config PASS on 2026-05-15. Immediate unlock confirmed (is​Pro false -> true) and entitlement refresh completed active.” 
• “Sandbox purchase-path PASS on 2026-05-17: verified purchase observed, immediate unlock (is​Pro false -> true), and entitlement refresh completed active."|

| [x] | Restore purchases | Restore succeeds and premium features unlock without restart |  |
• “Sandbox restore PASS on 2026-05-17: restore completed, entitlement revalidated active, and Pro remained unlocked without restart.”  |
| [x] | App relaunch persistence | Relaunch with active entitlement loads as Pro before gated flows are used |  |  
• “PASS on 2026-05-18: after force-quit/relaunch, init entitlement refresh set is​Pro false -> true and gated features were available immediately.”|
| [x] | Expired subscription behavior | Expired entitlement removes Pro access correctly and predictably |  |  
• “Sandbox expiry PASS on 2026-05-18: entitlement became inactive; is​Pro transitioned true -> false on refresh/relaunch; Pro gates (template limit + invite join) correctly redirected to paywall; restore did not re-enable Pro.”|
| [x] | Revoked/refunded behavior | Revoked/refunded transaction removes Pro access within listener refresh cycle |  |  
• “StoreKit local revoke PASS on May 18, 2026: revoked com​.pitchmark​.pro​.annual in Xcode Transaction Manager; listener refresh set is​Pro true -> false without restart.”|
| [x] | Offline launch behavior | App handles no-network startup gracefully with last-known state + later reconciliation |  |  
• “Offline launch PASS on May 18, 2026: with Airplane Mode cold start, app remained usable with graceful offline fallbacks; after reconnect, listeners refreshed and state reconciled to server values without restart.”|
| [x] | Paywall coverage audit | All Pro-gated features consistently route to paywall when `isPro == false` |  |  
“StoreKit paywall-coverage PASS on 2026-05-18: with Debug ​Subscription ​State = ​Off, Subscription ​Test ​Mode = ​Off, and is​Pro = false, all exercised Pro-gated flows consistently routed to Pro​Paywall​View (template pitch-limit gating, participant/invite join gating, and in-flow upgrade entry points). No bypass paths observed; non-Pro state remained enforced after refresh/relaunch and restore attempt.”|

## 2) App Store Compliance Package

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [x] | Privacy Policy URL | Live URL accessible, current, and linked in app + App Store Connect |  |  
• Privacy ​Policy ​URL | ​Live ​URL accessible, current, and linked in app + ​App ​Store ​Connect|
| [x] | Terms of Use URL | Live URL accessible and linked where required |  |  
• terms loads and in-app link opens that same /terms URL.|
| [x] | App Privacy Nutrition Label | Matches actual data collection/sharing and SDK behavior |  |  
• Matches actual data collection​/sharing and ​SDK behavior|
| [x] | Support URL | Points to valid support destination (`support@pitchmark.app` path included) |  |  |
| [x] | Export compliance answers | Encryption/export responses accurate in App Store Connect |  |  |
| [x] | IAP metadata completeness | Subscription name, duration, pricing, screenshots, review notes complete |  |  |

## 3) Reliability and Quality Gates

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [x] | Release build smoke test | Core app flows complete in Release config on physical device |  |  |
| [x] | Crash-free smoke cycle | No crashes across sign-in, game flow, subscription flow, restore |  |  |
| [x] | Network resilience | Graceful handling for poor network/timeouts in critical flows |  |  |
| [x] | Foreground/background stability | No state corruption or duplicate listeners after app lifecycle transitions |  |  |
| [x] | Debug log hygiene | Verbose debug logs reduced/guarded for production builds |  |  |

## 4) Security and Abuse Controls

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [x] | Firestore rules audit | Least-privilege rules validated with owner/non-owner/adversarial cases |  | 2026-05-21: Rules review + hardening pass completed. Validated auth gate, owner-only writes in `/users/{ownerUid}/...`, active-session scoped participant access for live game flows, and server-only writes for `/pitchers/{pitcherId}/stats/*`. Fixed least-privilege gap by tightening `/templates/*` and `/pitchers/*` `list` from any signed-in user to owner/shared/claimed-only. |
| [x] | Callable function validation | Server validates auth, input schema, and authorization for every callable |  | 2026-05-21: Audited all callable exports in `functions/src/index.ts` (1 callable: `createRetailCheckoutSession`). Enforced auth (`request.auth.uid` required), strict payload schema (object-only payload + typed/length-bounded/sanitized strings), allowed-value authorization (`itemKind` enum + `retailProductId` allowlist), and secure env config checks (HTTPS-only checkout redirect URLs). |
| [x] | Rate limiting strategy | Sensitive endpoints have abuse controls and retry-safe behavior |  | 2026-05-21: Added abuse controls to `createRetailCheckoutSession` in `functions/src/index.ts` — per-user throttle (max 5 attempts per 60s, server-enforced via Firestore transaction) + retry-safe idempotency key support (replays return the same checkout session payload instead of creating duplicates). |
| [ ] | App Check rollout | App Check enforcement plan defined and tested for production impact |  |  |
| [x] | Secret/config hygiene | No secrets in client repo; env vars and key scopes reviewed |  |  |

## 5) UX and Accessibility

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [x] | Empty/loading/error states | Every core screen has intentional and understandable fallback states |  | 2026-05-21 audit: Sign-in shows inline auth errors (`SignInView.swift`); Settings covers empty/error/loading states for templates, pitchers, and stats (`SettingsView.swift`: \"No templates/pitchers...\", `ProgressView`, inline error text/alerts); Storefront includes checkout loading + explicit checkout/subscription errors (`Retail.swift`: `ProgressView(\"Preparing checkout…\")`, `lastErrorMessage`); Tracker includes loading indicators, empty-state text, and targeted alerts/errors for join/share/camera/heatmap flows (`PitchTrackerView.swift`: \"Loading stats…\", \"No pitches recorded\", alert-backed error surfaces). |
| [x] | Purchase UX clarity | Pending/cancel/failure/success states are explicit and user-friendly |  | 2026-05-21: Added explicit user-facing purchase state messaging in subscription flows. `SubscriptionManager` now publishes status text for success/cancel/restore outcomes and friendly failure messaging for network/store errors; surfaced in both Pro paywall and Store screens (`SubscriptionManager.swift`, `Retail.swift`). Pending state remains explicit via in-button progress/disabled state + pending error text. |
| [x] | Restore discoverability | Restore Purchases is easy to find and communicates outcome clearly |  | 2026-05-21: `Restore Purchases` is prominently exposed in both subscription surfaces (Store screen and Pro paywall). Restore flow now returns explicit outcome messaging: success (`Purchases restored. PitchMark Pro is active.`), no-active-purchases (`No active purchases were found to restore.`), and friendly network/store failure text. |
| [x] | Dynamic Type support | Core screens remain usable at large accessibility text sizes |  | 2026-05-21: Implemented targeted AX text-size hardening on core flows. Sign-in buttons now use flexible width (`maxWidth`) and status text can wrap without clipping (`SignInView.swift`). Pro paywall content is scrollable for large text and primary purchase CTA supports multi-line wrapping (`SubscriptionManager.swift`). Settings action/footer labels now support multi-line + scale-down safeguards for long text (`SettingsView.swift`). Store title switched from fixed point size to dynamic text style (`Retail.swift`). |
| [x] | VoiceOver labels | Interactive controls have meaningful accessibility labels/traits |  | 2026-05-21: Added explicit accessibility labels/hints on core interactive controls. Sign-in methods and OTP controls now have descriptive VoiceOver labels/hints (`SignInView.swift`). Purchase/restore/close actions in Pro paywall include actionable VoiceOver hints (`SubscriptionManager.swift`). Store purchase/restore controls include explicit restore/purchase hints (`Retail.swift`). Key Settings actions (`Join a Game`, account footer button) now expose meaningful labels/hints (`SettingsView.swift`). |
| [x] | Color contrast and tap targets | Meets baseline accessibility expectations on real devices |  | 2026-05-21: Accessibility hardening pass completed on core flows. Enforced 44pt minimum tap targets on primary actions in sign-in/paywall/store/settings (`SignInView.swift`, `SubscriptionManager.swift`, `Retail.swift`, `SettingsView.swift`), including purchase/restore/join/account actions. Improved sign-in success/status text contrast from secondary gray to primary where appropriate. Verified no diagnostics issues after changes. |

## 6) Operations and Support Readiness

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [x] | Support workflow | Intake, response SLA, and escalation flow documented |  | 2026-05-21: Documented intake channel, severity triage, response SLA, escalation path, and closure process in `docs/SUPPORT_WORKFLOW.md`. |
| [x] | Incident playbook | Defined response for auth outage, StoreKit outage, Firestore outage |  | 2026-05-21: Added outage response playbook covering Firebase Auth, StoreKit, and Firestore incidents in `docs/INCIDENT_PLAYBOOK.md` (detection, immediate actions, user communication, recovery checks, escalation, closure). |
| [x] | Release rollback plan | Clear rollback path for bad build or major production issue |  | 2026-05-21: Documented rollback triggers, immediate actions, binary/backend rollback paths, verification steps, and closure flow in `docs/RELEASE_ROLLBACK_PLAN.md`. |
| [x] | Versioned release notes | Internal and external release notes drafted and reviewed |  | 2026-05-21: Drafted versioned internal + external notes in `docs/RELEASE_NOTES_v1.0.0-rc1.md` (compliance, security, UX/accessibility, operational updates). |

## 7) TestFlight Release Candidate Process

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [ ] | RC build selected | One build tagged as release candidate |  |  |
| [ ] | Fixed test script | Shared checklist used by all testers for consistent coverage |  |  |
| [ ] | External tester pass | 5-10 testers complete script on real devices |  |  |
| [ ] | Triage complete | All P0/P1 issues fixed or formally waived with rationale |  |  |
| [ ] | Final go/no-go review | Explicit launch decision recorded with sign-off |  |  |

## Launch Blockers (Do Not Submit If Any Open)

- [ ] Subscription purchase or restore fails in Sandbox/TestFlight
- [ ] Premium gating is inconsistent
- [ ] Firestore rules permit unauthorized access
- [ ] Privacy/App Store compliance fields incomplete or inaccurate
- [ ] Reproducible crash in primary user flows

## Notes

- Date:
- Decision:
- Follow-ups:
