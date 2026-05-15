/**
 * Data access contract for Salesforce Digital Wallet's Consumption Tagging
 * objects (TenantEnrichedUsageEvent DLO and Consumption Insights DMO).
 *
 * Wallet data is the authoritative source of Flex Credit consumption when
 * available, but it is only provisioned in Wallet-enabled production orgs.
 * Sandboxes, scratch orgs, Data Cloud One companion orgs, and trial orgs
 * without a consumption-product purchase do not have these objects.
 * Implementations MUST surface availability through `isWalletAvailable()`
 * and MUST NOT throw when Wallet objects are absent — the cost path falls
 * back to FluentMetric AI's tier-rate estimate when Wallet is unavailable.
 *
 * See Documents/WALLET-LIVE-SCHEMA.md for the doc-derived field reference
 * and the verification checklist for hardening against a real prod org.
 */
public interface IAiWalletDAO {
    /**
     * Cheap probe — `SELECT count() FROM TenantEnrichedUsageEvent__dlm LIMIT 1`
     * wrapped in a try/catch that returns false on any QueryException
     * (object missing, no data-space mapping, no permission, etc.). The
     * implementation SHOULD cache the result for the duration of the
     * transaction.
     */
    Boolean isWalletAvailable();

    /**
     * Total Flex Credits consumed within the date range. Returns null when
     * Wallet is unavailable so callers can distinguish "no Wallet" from
     * "zero credits".
     */
    Decimal getTotalFlexCredits(DateTime startDate, DateTime endDate);

    /**
     * Wallet aggregates grouped by the requested standard-tag dimension.
     * `groupBy` accepts: `RESOURCE`, `ROOT_RESOURCE`, `FEATURE`, `USAGE_TYPE`,
     * or `DATA_SPACE`. Returns an empty list when Wallet is unavailable.
     */
    List<WalletAggregateDTO> getFlexCreditAggregates(DateTime startDate, DateTime endDate, String groupBy);

    /**
     * Per-prompt Flex Credits using ResourceIdOrApiName as the prompt API
     * name (per the Wallet GenAI prompts help article). Empty list when
     * Wallet is unavailable.
     */
    List<WalletAggregateDTO> getFlexCreditByPrompt(DateTime startDate, DateTime endDate);

    /**
     * Per-user Flex Credits. The verified live DLO carries `userid__c`,
     * so Wallet can attribute consumption to a Salesforce User Id when the
     * triggering action was user-initiated. Empty list when Wallet is
     * unavailable. Rows with null/empty `userid__c` are bucketed under
     * the sentinel key `NOT_SET` (matching the FluentMetric AI convention
     * already used in the GenAIGatewayRequest path).
     */
    List<WalletAggregateDTO> getFlexCreditByUser(DateTime startDate, DateTime endDate);

    /**
     * Per-custom-tag Flex Credits read from the Consumption Insights
     * Extended SDM. Returns an empty list when either Wallet or the
     * Extended SDM is unavailable (the Extended SDM is currently in pilot).
     */
    List<WalletAggregateDTO> getFlexCreditByCustomTag(DateTime startDate, DateTime endDate);
}
