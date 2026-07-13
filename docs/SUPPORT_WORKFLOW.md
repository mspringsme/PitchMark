# PitchMark Support Workflow

## Intake
- Primary intake channel: `https://pitchmark.app/support`
- Support URL: `https://pitchmark.app/support`
- User should include:
  - account email
  - device model + iOS version
  - app version/build number
  - issue summary and reproduction steps
  - screenshots/screen recordings if available

## Triage
- Severity levels:
  - `SEV-1`: app crash, data loss, blocked sign-in/purchase for many users
  - `SEV-2`: major feature unusable for one user/group
  - `SEV-3`: minor bug, UX issue, non-blocking defect
- Assign owner for each ticket and track status: `new`, `investigating`, `mitigated`, `resolved`.

## Response SLA
- Initial acknowledgment:
  - `SEV-1`: within 4 hours
  - `SEV-2`: within 1 business day
  - `SEV-3`: within 2 business days
- Status updates:
  - `SEV-1`: every 24 hours until mitigated
  - `SEV-2/3`: every 2-3 business days until resolved

## Escalation Flow
1. Support triages and reproduces issue.
2. If backend/security/payment impact is suspected, escalate immediately to engineering owner.
3. If App Store billing/subscription issue is Apple-side, route user to Apple subscription support and document handoff.
4. If security/privacy concern exists, escalate to security/privacy owner and prioritize as `SEV-1` or `SEV-2` based on impact.
5. If unresolved beyond SLA, escalate to product owner for priority decision and customer communication.

## Closure
- Confirm fix or workaround with the reporter.
- Record root cause and prevention note.
- Link code/config change (if applicable) in release notes or internal changelog.
