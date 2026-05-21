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
| [ ] | Firestore rules audit | Least-privilege rules validated with owner/non-owner/adversarial cases |  |  |
| [ ] | Callable function validation | Server validates auth, input schema, and authorization for every callable |  |  |
| [ ] | Rate limiting strategy | Sensitive endpoints have abuse controls and retry-safe behavior |  |  |
| [ ] | App Check rollout | App Check enforcement plan defined and tested for production impact |  |  |
| [ ] | Secret/config hygiene | No secrets in client repo; env vars and key scopes reviewed |  |  |

## 5) UX and Accessibility

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [ ] | Empty/loading/error states | Every core screen has intentional and understandable fallback states |  |  |
| [ ] | Purchase UX clarity | Pending/cancel/failure/success states are explicit and user-friendly |  |  |
| [ ] | Restore discoverability | Restore Purchases is easy to find and communicates outcome clearly |  |  |
| [ ] | Dynamic Type support | Core screens remain usable at large accessibility text sizes |  |  |
| [ ] | VoiceOver labels | Interactive controls have meaningful accessibility labels/traits |  |  |
| [ ] | Color contrast and tap targets | Meets baseline accessibility expectations on real devices |  |  |

## 6) Operations and Support Readiness

| Status | Item | Pass Criteria | Owner | Evidence |
|---|---|---|---|---|
| [ ] | Support workflow | Intake, response SLA, and escalation flow documented |  |  |
| [ ] | Incident playbook | Defined response for auth outage, StoreKit outage, Firestore outage |  |  |
| [ ] | Release rollback plan | Clear rollback path for bad build or major production issue |  |  |
| [ ] | Versioned release notes | Internal and external release notes drafted and reviewed |  |  |

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
