# PitchMark Incident Playbook

## Scope
This playbook defines response steps for:
- Firebase Auth outage
- StoreKit / App Store purchase outage
- Firestore outage or severe degradation

## Severity
- `SEV-1`: Widespread outage blocking core app usage or purchases.
- `SEV-2`: Major degradation with partial workaround.
- `SEV-3`: Minor impact, non-critical path.

## Common Response Workflow
1. Acknowledge incident and assign incident owner.
2. Confirm blast radius (which flow, which users, which platform).
3. Post user-facing status message (in-app fallback copy or support response template).
4. Mitigate (feature flag / temporary fallback / disable failing path).
5. Monitor recovery and verify core flows.
6. Close with post-incident notes (root cause + prevention).

## Firebase Auth Outage

### Detection signals
- Sign-in failures spike.
- Apple / Google sign-in callbacks failing.
- Auth-related cloud function errors increase.

### Immediate actions
1. Confirm Firebase status and regional impact.
2. Keep existing signed-in sessions active where possible.
3. Show clear sign-in failure messaging: temporary auth service issue, retry later.
4. Halt non-essential auth-dependent operations to avoid cascading errors.

### User communication
- Support response: acknowledge outage, no user action required beyond retry.
- Provide expected retry interval and status updates.

### Recovery checks
- Apple and Google sign-in work.
- Session persistence remains intact after relaunch.

## StoreKit / Purchase Outage

### Detection signals
- Purchase start/restore calls failing with network/store errors.
- Spike in restore/purchase error banners.

### Immediate actions
1. Confirm Apple System Status for App Store / In-App Purchases.
2. Keep paywall accessible but show clear actionable messaging.
3. Avoid repeated retry loops; throttle retries and keep UI responsive.
4. Preserve idempotency behavior for checkout/session creation.

### User communication
- Explain temporary App Store issue and suggest retry later.
- For existing subscribers, guide to Restore Purchases after outage recovers.

### Recovery checks
- Purchase success path works.
- Restore Purchases returns expected status.
- Subscription entitlement refresh is correct.

## Firestore Outage

### Detection signals
- Listener/read/write failures across tracker/settings/live flows.
- Elevated timeout/network error rates.

### Immediate actions
1. Confirm Firebase status and Firestore regional health.
2. Keep app stable with graceful offline/error states.
3. Defer non-critical writes where possible; avoid destructive retries.
4. Protect data consistency (do not duplicate writes/events on reconnect).

### User communication
- Tell users data sync is temporarily unavailable.
- Explain that local usage may continue where possible and will sync when recovered.

### Recovery checks
- Core reads/writes succeed for:
  - game/session loading
  - pitch event save
  - live join/share flows
- No duplicate/invalid records after reconnect.

## Escalation Matrix
- Incident owner: primary app engineer on-call.
- Secondary: backend/functions owner.
- Product/owner escalation: if SEV-1 exceeds 2 hours.
- Security/privacy escalation: if data exposure or integrity risk is suspected.

## Post-Incident Closure
1. Document timeline and impact.
2. Record root cause.
3. Add prevention actions (monitoring, guardrails, UI fallback improvements).
4. Link remediation PR/commit and checklist updates.
