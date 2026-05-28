// scripts/verify-actions.apex
//
// Anonymous Apex smoke test executed by scripts/verify-tableau.sh.
// Invokes a representative set of agent invocable actions and prints
// VERIFY_RESULT::OK::{check}::... or VERIFY_RESULT::FAIL::{check}::...
// markers that the shell script greps for. Verifies that the Lightning
// edition's AiInsightsService is reachable from the Tableau edition's
// invocable surface, including the new adoption-parity actions.
//
// Markers emitted:
//   - overview                — GetUsageOverviewAction (legacy check)
//   - adoption_entitlement    — GetEntitlementSnapshotAction
//   - adoption_deltas         — GetAdoptionDeltasAction (WoW)

// --- 1. Usage overview ------------------------------------------------------
GetUsageOverviewAction.Request overviewReq = new GetUsageOverviewAction.Request();
List<GetUsageOverviewAction.Response> overviewOut = GetUsageOverviewAction.run(
    new List<GetUsageOverviewAction.Request>{ overviewReq }
);

if (overviewOut == null || overviewOut.isEmpty()) {
    System.debug('VERIFY_RESULT::FAIL::overview::no response returned');
} else {
    GetUsageOverviewAction.Response r = overviewOut[0];
    if (r.dateRangeLabel != null && r.dateRangeLabel.startsWith('Error:')) {
        System.debug('VERIFY_RESULT::FAIL::overview::' + r.dateRangeLabel);
    } else {
        System.debug('VERIFY_RESULT::OK::overview::totalRequests=' + r.totalRequests
            + ' uniqueUsers=' + r.uniqueUsers
            + ' acceptanceRate=' + r.acceptanceRateLabel
            + ' window=' + r.dateRangeLabel);
    }
}

// --- 2. Entitlement snapshot ------------------------------------------------
GetEntitlementSnapshotAction.Request entReq = new GetEntitlementSnapshotAction.Request();
List<GetEntitlementSnapshotAction.Response> entOut = GetEntitlementSnapshotAction.run(
    new List<GetEntitlementSnapshotAction.Request>{ entReq }
);

if (entOut == null || entOut.isEmpty()) {
    System.debug('VERIFY_RESULT::FAIL::adoption_entitlement::no response returned');
} else {
    GetEntitlementSnapshotAction.Response r = entOut[0];
    if (r.adoptionRateLabel != null && r.adoptionRateLabel.startsWith('Error:')) {
        System.debug('VERIFY_RESULT::FAIL::adoption_entitlement::' + r.adoptionRateLabel);
    } else {
        System.debug('VERIFY_RESULT::OK::adoption_entitlement::entitled=' + r.entitledCount
            + ' active=' + r.activeCount
            + ' adoptionRate=' + r.adoptionRateLabel
            + ' fallback=' + r.entitledFallback);
    }
}

// --- 3. Org adoption deltas (WoW) -------------------------------------------
GetAdoptionDeltasAction.Request deltaReq = new GetAdoptionDeltasAction.Request();
List<GetAdoptionDeltasAction.Response> deltaOut = GetAdoptionDeltasAction.run(
    new List<GetAdoptionDeltasAction.Request>{ deltaReq }
);

if (deltaOut == null || deltaOut.isEmpty()) {
    System.debug('VERIFY_RESULT::FAIL::adoption_deltas::no response returned');
} else {
    GetAdoptionDeltasAction.Response r = deltaOut[0];
    Boolean errored = r.weeksJson != null
        && r.weeksJson.contains('"error":true');
    if (errored) {
        System.debug('VERIFY_RESULT::FAIL::adoption_deltas::' + r.weeksJson);
    } else {
        System.debug('VERIFY_RESULT::OK::adoption_deltas::requestsWow=' + r.latestRequestsWowPctLabel
            + ' usersWow=' + r.latestUsersWowPctLabel
            + ' tokensWow=' + r.latestTokensWowPctLabel
            + ' latestWeek=' + r.latestWeekIsoLabel);
    }
}
