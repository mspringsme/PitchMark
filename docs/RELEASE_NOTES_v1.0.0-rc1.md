# PitchMark Release Notes (v1.0.0-rc1)

Date: 2026-05-21

## External Release Notes (App Store)
- Improved subscription experience with clearer purchase/restore outcome messaging.
- Added in-app legal links for Privacy Policy and Terms of Use.
- Improved accessibility support, including better Dynamic Type behavior and VoiceOver labels in core flows.
- Stability and reliability improvements across settings, sign-in, and tracking experiences.

## Internal Release Notes

### Compliance and Readiness
- Privacy Policy URL and Terms URL wired in app and hosted endpoints.
- Support URL endpoint and support workflow documentation added.
- Incident playbook documented for Auth, StoreKit, and Firestore outages.

### Security
- Firestore rules least-privilege hardening:
  - tightened top-level list access for templates and pitchers.
- Callable function hardening:
  - strict auth and input validation,
  - HTTPS env URL validation.
- Added checkout abuse controls:
  - per-user rate limit window,
  - idempotency key support for retry-safe checkout creation.

### UX / Accessibility
- Purchase flow now shows explicit pending/cancel/failure/success messaging.
- Restore Purchases messaging improved (restored / no purchases / failure).
- Dynamic Type improvements in sign-in, paywall, settings, and store title.
- VoiceOver labels/hints added for core interactive controls.
- Tap target hardening on primary controls.

### Operational Notes
- App Check provider registration plan documented; monitor-first enforcement strategy retained.
- Debug log hygiene improved with debug-only logging helper.

## Reviewer Notes Summary (for App Review field)
- Paywall location: Settings → Store.
- Restore Purchases available in Store and Pro paywall.
- Pro-gated flow: Join Game participant/invite features.
