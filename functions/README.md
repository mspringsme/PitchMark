# PitchMark Firebase Functions

If you're setting this project up on Windows to help with the website, see [`../docs/WINDOWS_SETUP.md`](../docs/WINDOWS_SETUP.md).

## Callable functions
- `createRetailCheckoutSession`
- `deleteAccount`

`createRetailCheckoutSession` expects:
- `retailProductId`: one of `grid_5x3`, `grid_3_5x2_75`, `grid_custom`, `sheet_8_5x11`
- `itemKind`
- `templateId`
- `templateName`
- `storeTemplateName`

`createRetailCheckoutSession` returns:
- `checkoutUrl`
- `sessionId`
- `displayName`

`deleteAccount` requires an authenticated Firebase user. It removes the user's private Firestore tree, removes or unlinks user-owned/shared references, unlinks retained retail order records from the Firebase account, and deletes the Firebase Auth user.

## Setup
1. Copy `.env.example` to your deployed function env/config and set real values.
2. Replace placeholder Stripe `price_*` IDs in `src/index.ts` with your real Stripe Price IDs.
3. Deploy functions.

## Admin claim helper
If you need to mark your owner account as an admin for the app UI and Firestore rules, run:

```bash
node scripts/setAdminClaim.js --email your@email.com
```

You can also pass `--uid <firebase-uid>` instead of `--email`.

## Notes
- Function requires authenticated Firebase user.
- Metadata is attached to both Checkout Session and PaymentIntent.
