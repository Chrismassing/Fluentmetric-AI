/**
 * Small formatting helpers for the FluentMetric AI overview cards.
 * Kept in a shared module so future components can reuse the same
 * "2.1M / 340K" abbreviation logic.
 */

/**
 * Abbreviate a number for compact display.
 *   1_234       -> "1.2K"
 *   2_100_000   -> "2.1M"
 *   3_450_000_0 -> "34.5M"
 *   below 1000  -> "123"
 */
export function abbreviateNumber(value) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return '0';
    }
    const n = Number(value);
    const abs = Math.abs(n);
    if (abs < 1000) {
        return String(Math.round(n));
    }
    if (abs < 1_000_000) {
        return `${trimZero(n / 1000)}K`;
    }
    if (abs < 1_000_000_000) {
        return `${trimZero(n / 1_000_000)}M`;
    }
    return `${trimZero(n / 1_000_000_000)}B`;
}

/**
 * Format a ratio (0..1) or percent (0..100) as a one-decimal percentage.
 * Detects the scale by magnitude: values <= 1 are treated as ratios.
 */
export function formatPercent(value) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return '0%';
    }
    const n = Number(value);
    const pct = Math.abs(n) <= 1 ? n * 100 : n;
    return `${trimZero(pct)}%`;
}

/**
 * One-decimal max, trailing zeros removed.
 *   1.00 -> "1"
 *   1.05 -> "1.1"
 *   0.9  -> "0.9"
 */
function trimZero(n) {
    const rounded = Math.round(n * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}
