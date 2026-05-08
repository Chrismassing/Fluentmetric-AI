/**
 * Local copy of the numberFormat helpers. Cross-bundle LWC imports are
 * fragile in managed packages, so each dashboard bundle carries its own.
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

/**
 * Relative time label ("2 days ago", "just now", "in 3 hours"). Falls back
 * to the ISO string for values too old to matter (> 1 year). The modal
 * pairs this with the raw timestamp in a title attribute so users can hover
 * for the full date.
 */
export function relativeTime(value) {
    if (!value) return '—';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '—';
    const diffMs = Date.now() - d.getTime();
    const absMs = Math.abs(diffMs);
    const suffix = diffMs >= 0 ? 'ago' : 'from now';
    const minute = 60 * 1000;
    const hour = 60 * minute;
    const day = 24 * hour;
    const week = 7 * day;
    const month = 30 * day;
    const year = 365 * day;

    if (absMs < minute) return 'just now';
    if (absMs < hour) {
        const n = Math.round(absMs / minute);
        return `${n} minute${n === 1 ? '' : 's'} ${suffix}`;
    }
    if (absMs < day) {
        const n = Math.round(absMs / hour);
        return `${n} hour${n === 1 ? '' : 's'} ${suffix}`;
    }
    if (absMs < week) {
        const n = Math.round(absMs / day);
        return `${n} day${n === 1 ? '' : 's'} ${suffix}`;
    }
    if (absMs < month) {
        const n = Math.round(absMs / week);
        return `${n} week${n === 1 ? '' : 's'} ${suffix}`;
    }
    if (absMs < year) {
        const n = Math.round(absMs / month);
        return `${n} month${n === 1 ? '' : 's'} ${suffix}`;
    }
    const n = Math.round(absMs / year);
    return `${n} year${n === 1 ? '' : 's'} ${suffix}`;
}

function trimZero(n) {
    const rounded = Math.round(n * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}
