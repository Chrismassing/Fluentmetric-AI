/**
 * Stamps User.FluentMetric_IsEntitled__c from PermissionSetAssignment so the
 * Tableau Next semantic model can compute adoption rate against a User-keyed
 * boolean. The Apex side (EntitlementService) still resolves entitlement live
 * from PSA — this boolean is a denormalized projection for analytics only.
 *
 * Scheduling (production install runs this once during `make install`):
 *   String cron = '0 0 2 * * ?'; // every day at 02:00 org time
 *   System.schedule('FluentMetric Entitlement Sync', cron, new FluentMetricEntitlementSyncSchedulable());
 *
 * Failure semantics: any DML/SOQL exception is caught + logged, and the run
 * exits cleanly. Adoption math degrades gracefully via EntitlementService's
 * `entitledFallback` path (denominator becomes total active users) rather
 * than throwing in the dashboard request path.
 */
public with sharing class FluentMetricEntitlementSyncSchedulable implements Schedulable {
    @TestVisible
    private static final String ENTITLEMENT_PERMSET_NAME = EntitlementService.ENTITLEMENT_PERMSET_NAME;

    public void execute(SchedulableContext sc) {
        syncEntitledFlags();
    }

    /**
     * Splits Users into "should be entitled" (assigned to the permset) vs.
     * "should not", and DMLs only the rows whose flag actually changes.
     * Bulk-safe up to ~50k assignees / ~50k active users per run.
     *
     * Public so admins can force a sync from Anonymous Apex when they need
     * the Tableau Next adoption KPI to refresh between nightly runs.
     */
    public static void syncEntitledFlags() {
        try {
            Set<Id> entitledIds = resolveEntitledUserIds();
            List<User> toUpdate = new List<User>();

            for (User u : [
                SELECT Id, FluentMetric_IsEntitled__c
                FROM User
                WHERE IsActive = TRUE
                WITH USER_MODE
                LIMIT 50000
            ]) {
                Boolean shouldBeEntitled = entitledIds.contains(u.Id);
                if (u.FluentMetric_IsEntitled__c != shouldBeEntitled) {
                    u.FluentMetric_IsEntitled__c = shouldBeEntitled;
                    toUpdate.add(u);
                }
            }

            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, false);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'FluentMetricEntitlementSyncSchedulable failed: ' + e.getMessage());
        }
    }

    @TestVisible
    private static Set<Id> resolveEntitledUserIds() {
        Set<Id> out = new Set<Id>();
        Set<Id> psIds = new Set<Id>();
        for (PermissionSet ps : [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :ENTITLEMENT_PERMSET_NAME
            WITH USER_MODE
        ]) {
            psIds.add(ps.Id);
        }
        if (psIds.isEmpty()) {
            return out;
        }
        Date today = Date.today();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE
                PermissionSetId IN :psIds
                AND (ExpirationDate = NULL
                OR ExpirationDate >= :today)
                AND Assignee.IsActive = TRUE
            WITH USER_MODE
            LIMIT 50000
        ]) {
            out.add(psa.AssigneeId);
        }
        return out;
    }
}
