// Which size a printed card order (grid key or Batter & Runner Grid) prints
// at. Mirrors GridKeyProduct in PitchMark/GridKeyPrint.swift - keep the
// sizes and custom limits the same.

export type GridKeyPrintSize = { widthInches: number; heightInches: number };

export const gridKeyFixedSizes: Record<string, GridKeyPrintSize> = {
    grid_5x3: { widthInches: 5, heightInches: 3 },
    grid_3_5x2_75: { widthInches: 3.5, heightInches: 2.75 }
};

export const gridKeyCustomProductId = "grid_custom";
/** Batter & Runner Grid: always the size chosen in the app. */
export const signGridProductId = "sign_grid_custom";
const customSizedProductIds = new Set([gridKeyCustomProductId, signGridProductId]);
const customWidthRange = { min: 3, max: 7 };
const customHeightRange = { min: 2, max: 5 };
const customStep = 0.25;

function onStep(value: number): boolean {
    const steps = value / customStep;
    return Math.abs(steps - Math.round(steps)) < 0.0001;
}

export function isValidCustomSize(size: GridKeyPrintSize): boolean {
    const { widthInches: w, heightInches: h } = size;
    return Number.isFinite(w) && Number.isFinite(h)
        && w >= customWidthRange.min && w <= customWidthRange.max
        && h >= customHeightRange.min && h <= customHeightRange.max
        && onStep(w) && onStep(h);
}

export type PrintSizeResolution =
    | { ok: true; size: GridKeyPrintSize | null }
    | { ok: false; message: string };

/**
 * Standard products print at their own size whatever the client sent.
 * A custom product prints at the requested size, which must be in range and
 * on a quarter inch. A custom request with no size at all comes from an app
 * build that never sent one - it is refused (user's call, 2026-11-08), so a
 * custom card can't be sold without knowing what to print.
 */
export function resolveGridKeyPrintSize(
    retailProductId: string,
    requestedWidth: unknown,
    requestedHeight: unknown
): PrintSizeResolution {
    const fixed = gridKeyFixedSizes[retailProductId];
    if (fixed) {
        return { ok: true, size: fixed };
    }
    if (!customSizedProductIds.has(retailProductId)) {
        return { ok: true, size: null };
    }
    if (requestedWidth == null && requestedHeight == null) {
        return {
            ok: false,
            message: "Update PitchMark to order a custom size - this version doesn't send the size to print."
        };
    }
    if (typeof requestedWidth !== "number" || typeof requestedHeight !== "number") {
        return { ok: false, message: "Custom size must give a width and a height in inches." };
    }
    const size = { widthInches: requestedWidth, heightInches: requestedHeight };
    if (!isValidCustomSize(size)) {
        return {
            ok: false,
            message: "Custom size must be 3 to 7 in wide and 2 to 5 in tall, in quarter inches."
        };
    }
    return { ok: true, size };
}

/** Reads the size back off Checkout Session metadata (strings). */
export function printSizeFromMetadata(metadata: Record<string, string>): GridKeyPrintSize | null {
    const w = Number(metadata.printWidthInches);
    const h = Number(metadata.printHeightInches);
    if (!metadata.printWidthInches || !metadata.printHeightInches || !(w > 0) || !(h > 0)) {
        return null;
    }
    return { widthInches: w, heightInches: h };
}
