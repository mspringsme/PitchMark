# PitchMark Firebase Functions

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

## Notes
- Function requires authenticated Firebase user.
- Metadata is attached to both Checkout Session and PaymentIntent.
