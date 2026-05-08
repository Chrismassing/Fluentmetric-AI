/**
 * Bundle entry so Salesforce treats `c/aiInsightsTooltips` as a valid LWC
 * module. Re-exports the TOOLTIPS constant from tooltips.js so consumers can
 * use either:
 *   import { TOOLTIPS } from 'c/aiInsightsTooltips';
 *   import { TOOLTIPS } from 'c/aiInsightsTooltips/tooltips';
 */
export { TOOLTIPS, lookupTooltip } from './tooltips';
