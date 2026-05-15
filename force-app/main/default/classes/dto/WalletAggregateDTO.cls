/**
 * Aggregate row from Salesforce Digital Wallet's TenantEnrichedUsageEvent DLO.
 *
 * One row per (groupKey, dimension-tuple) combination within the requested
 * date range. `flexCredits` is the SUM of unitsConsumed__c for that group.
 *
 * The DAO populates the dimension fields it can — others remain null. UI
 * consumers should treat null as "not attributed" rather than zero.
 *
 * Wallet does not natively attribute consumption to a Salesforce User Id —
 * use the FluentMetric estimate path for per-user cost. Wallet attributes
 * to: Resource (typically the GenAI prompt API name), Root Resource (the
 * agent or source that owns the action), Feature, Usage Type, and any
 * org-defined Custom Tags. See Documents/WALLET-LIVE-SCHEMA.md for the
 * doc-derived field reference.
 */
public class WalletAggregateDTO {
    @AuraEnabled
    public String groupKey;

    @AuraEnabled
    public String groupLabel;

    @AuraEnabled
    public Decimal flexCredits;

    @AuraEnabled
    public String userId;

    @AuraEnabled
    public String resourceIdOrApiName;

    @AuraEnabled
    public String rootResourceIdOrApiName;

    @AuraEnabled
    public String resourceType;

    @AuraEnabled
    public String featureDeveloperName;

    @AuraEnabled
    public String usageType;

    @AuraEnabled
    public String dataSpace;

    /** Raw `Additional Info` JSON when present — UI may parse for custom tags. */
    @AuraEnabled
    public String additionalInfoJson;

    /** Custom-tag key/value when this row is sourced from the Extended SDM. */
    @AuraEnabled
    public String customTagKey;

    @AuraEnabled
    public String customTagValue;

    public WalletAggregateDTO() {
        this.flexCredits = 0;
    }
}
