/**
 * Compact number formatting helpers, mirrored from aiInsightsOverview.
 * LWC modules don't share local helpers across components — each component
 * bundle imports its own copy.
 */

export function abbreviateNumber(value) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return '0';
    }
    const n = Number(value);
    const abs = Math.abs(n);
    if (abs < 1000) return String(Math.round(n));
    if (abs < 1_000_000) return `${trimZero(n / 1000)}K`;
    if (abs < 1_000_000_000) return `${trimZero(n / 1_000_000)}M`;
    return `${trimZero(n / 1_000_000_000)}B`;
}

function trimZero(n) {
    const rounded = Math.round(n * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}
