# PitchMark Firebase Functions (Stripe)

## Added callable
- `createRetailCheckoutSession`

It expects:
- `retailProductId`: one of `grid_5x3`, `grid_3_5x2_75`, `grid_custom`, `sheet_8_5x11`
- `itemKind`
- `templateId`
- `templateName`
- `storeTemplateName`

It returns:
- `checkoutUrl`
- `sessionId`
- `displayName`

## Setup
1. Copy `.env.example` to your deployed function env/config and set real values.
2. Replace placeholder Stripe `price_*` IDs in `src/index.ts` with your real Stripe Price IDs.
3. Deploy functions.

## Notes
- Function requires authenticated Firebase user.
- Metadata is attached to both Checkout Session and PaymentIntent.
