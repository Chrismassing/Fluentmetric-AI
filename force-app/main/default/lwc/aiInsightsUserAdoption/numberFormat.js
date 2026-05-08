/**
 * Local copy of the number/percent formatting helpers. Keeping a per-bundle
 * copy instead of a cross-bundle import avoids LWC module resolution edge
 * cases; the helpers are tiny and stable.
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

export function formatPercent(value) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return '0%';
    }
    const n = Number(value);
    const pct = Math.abs(n) <= 1 ? n * 100 : n;
    return `${trimZero(pct)}%`;
}

function trimZero(n) {
    const rounded = Math.round(n * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}
