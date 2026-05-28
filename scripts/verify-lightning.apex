// FluentMetric AI — Lightning edition smoke test
//
// Anonymous Apex check that exercises every dashboard tab's primary
// controller entry point. Used by `make smoke-lightning TARGET_ORG=<alias>`
// after a deploy to confirm the controller surface compiles, returns
// non-null DTOs, and does not throw against a live (or empty) org.
//
// Pass criteria: prints "FluentMetric AI Lightning smoke: OK" and exits 0.
// Failure modes: System.AssertException (null DTO) or any uncaught
// exception from the controller / service / DAO layers.

DateTime startDt = DateTime.now().addDays(-30);
DateTime endDt   = DateTime.now();

// Overview tab
System.assertNotEquals(null, AiInsightsController.getOverview(startDt, endDt),         'getOverview returned null');
System.assertNotEquals(null, AiInsightsController.getOverviewTrends(startDt, endDt),   'getOverviewTrends returned null');

// Adoption tab
System.assertNotEquals(null, AiInsightsController.getEntitlementSnapshot(startDt, endDt), 'getEntitlementSnapshot returned null');
System.assertNotEquals(null, AiInsightsController.getAdoptionCohorts(startDt, endDt),     'getAdoptionCohorts returned null');
System.assertNotEquals(null, AiInsightsController.getOrgAdoptionDeltas(startDt, endDt),   'getOrgAdoptionDeltas returned null');
System.assertNotEquals(null, AiInsightsController.getPowerUserSegments(startDt, endDt),   'getPowerUserSegments returned null');
System.assertNotEquals(null, AiInsightsController.getFeatureAdoption(startDt, endDt),     'getFeatureAdoption returned null');

// Explorer tab
System.assertNotEquals(null, AiInsightsController.getUsageByUser(startDt, endDt),    'getUsageByUser returned null');
System.assertNotEquals(null, AiInsightsController.getUsageByPrompt(startDt, endDt),  'getUsageByPrompt returned null');
System.assertNotEquals(null, AiInsightsController.getTokenConsumption(startDt, endDt, 'model'), 'getTokenConsumption returned null');
System.assertNotEquals(null, AiInsightsController.getFilterFacets(startDt, endDt, 25), 'getFilterFacets returned null');

// Safety tab
System.assertNotEquals(null, AiInsightsController.getSafetyOverview(startDt, endDt), 'getSafetyOverview returned null');

// Cost tab — cost numbers flow through getOverview; settings come from getCostSettings
System.assertNotEquals(null, AiInsightsController.getCostSettings(), 'getCostSettings returned null');

System.debug('FluentMetric AI Lightning smoke: OK');
