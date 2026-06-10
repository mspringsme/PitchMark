# PitchMark Release Rollback Plan

## Trigger Conditions
- Widespread crash or launch failure after release.
- Auth, Firestore, or purchase flow outage tied to new build/config.
- Data integrity risk or severe regression in core game tracking flow.

## Immediate Actions (First 30 Minutes)
1. Freeze further rollout in App Store Connect / TestFlight.
2. Assign incident owner and start incident thread.
3. Confirm impact scope (OS versions, regions, signed-in state, subscription state).
4. Publish user-facing support status update.

## Rollback Paths

### 1) App Binary Rollback
- If current App Store release is bad, stop phased release and submit previous stable build as next hotfix baseline.
- For TestFlight, expire/disable the bad build for external testers and move testers to the last known good build.

### 2) Backend/Config Rollback
- Revert Firebase rules/functions/hosting to last known good deployment.
- Disable newly enabled App Check enforcement if it is causing production blocking.
- Revert risky feature flags or remote-config toggles to safe defaults.

### 3) Purchase Flow Mitigation
- Keep app usable without purchase attempts where possible.
- If checkout callable is unstable, fail fast with clear messaging and prevent repeated retries.

## Verification After Rollback
- Sign-in (Apple and Google) succeeds.
- Core game/session reads and writes succeed.
- Purchase UI loads; restore/purchase messaging behaves correctly.
- No elevated crash/error reports in first recovery window.

## Communication
- Internal updates every 30–60 minutes until mitigated.
- External support response includes issue acknowledgment, current status, and retry guidance.

## Closure
1. Confirm stable metrics for at least one monitoring window.
2. Publish root-cause summary and prevention actions.
3. Link corrective PRs/releases and update checklist evidence.
