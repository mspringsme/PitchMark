# Retail Fulfillment Workflow (Owner)

## Purpose
Standard process to receive Stripe orders, prepare print assets, print, ship, and update customer-visible status in PitchMark.

## Tools
- PitchMark app (signed in with the admin/owner account)
- Stripe Dashboard (test/live as applicable)
- Printer workflow (PDF/template production)
- Shipping label provider (USPS/UPS/etc.)

## Order Status Model
- `new`: order received, not yet queued
- `queued`: print asset prepared, ready for print batch
- `printed`: physically printed, awaiting packing/shipping
- `shipped`: shipped with carrier + tracking entered
- `canceled`: canceled/refunded, not to be fulfilled
- `payment_failed`: payment did not complete

## Daily Workflow

### 1) Intake
1. Open PitchMark as the admin/owner account.
2. Go to `Store` → `Fulfillment Queue`.
3. Filter to `new`.
4. For each order, review:
- item/template name
- customer email
- payment status
- shipping address

### 2) Generate Order Packet
1. Open the order row.
2. Tap `Export Order Packet`.
3. Save packet to Files using this naming convention:
- `YYYY-MM-DD_order_<orderId>.txt`
4. Packet contains:
- order metadata
- shipping address
- immutable template snapshot JSON (`orderedTemplateSnapshotJson`)

### 3) Prepare Print Asset
1. From the packet, use `orderedTemplateSnapshotJson` as the source-of-truth.
2. Build/verify the print-ready asset for that specific order (do not rely on current editable user template).
3. Save print file using:
- `YYYY-MM-DD_print_<orderId>_<item>.pdf`
4. Update order status in app to `queued`.

### 4) Print Batch
1. Print all `queued` orders in a batch.
2. Perform quality check:
- legibility
- alignment
- quantity
- template/version match against packet
3. Mark each successful order as `printed`.

### 5) Pack and Ship
1. Package printed inserts/sheets.
2. Buy shipping label.
3. Enter in order row:
- `shippingCarrier`
- `trackingNumber`
4. Set status to `shipped`.

### 6) Customer Visibility Check
1. Confirm customer-side `Order History` now reflects updated fulfillment status.
2. Spot-check one shipped order each day.

## Exception Handling

### Payment failed/canceled
- Set or keep status as `payment_failed` or `canceled`.
- Do not print/ship.

### Missing shipping address
- Hold fulfillment.
- Contact customer via the support workflow.
- Keep status `new` or use internal note process.

### Template ambiguity
- Use snapshot JSON in order packet.
- If snapshot missing, escalate and hold before printing.

## End-of-Day Reconciliation
1. Compare Stripe paid sessions vs `retailOrders` count for the day.
2. Verify no orders are stuck in `new` unintentionally.
3. Verify all shipped orders have tracking.

## Production Go-Live Notes
- Ensure live Stripe webhook is configured and healthy.
- Ensure the owner/admin account can access Fulfillment Queue.
- Keep this SOP versioned with release notes.
