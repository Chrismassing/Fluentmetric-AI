/**
 * Test double for IAiWalletDAO.
 *
 * Wallet DLOs (TenantEnrichedUsageEvent, ConsumptionInsightsExtended) are
 * not present in cvk-dev or any sandbox/scratch org, so service tests inject
 * this mock. Defaults to Wallet-unavailable so tests of the estimate-fallback
 * path don't need to opt in.
 */
@IsTest
public class AiWalletDAOMock implements IAiWalletDAO {
    public Boolean walletAvailable = false;
    public Decimal totalFlexCreditsToReturn = 0;
    public List<WalletAggregateDTO> aggregatesToReturn = new List<WalletAggregateDTO>();
    public List<WalletAggregateDTO> byPromptToReturn = new List<WalletAggregateDTO>();
    public List<WalletAggregateDTO> byUserToReturn = new List<WalletAggregateDTO>();
    public List<WalletAggregateDTO> byCustomTagToReturn = new List<WalletAggregateDTO>();

    public Boolean isWalletAvailable() {
        return walletAvailable;
    }

    public Decimal getTotalFlexCredits(DateTime startDate, DateTime endDate) {
        return walletAvailable ? totalFlexCreditsToReturn : null;
    }

    public List<WalletAggregateDTO> getFlexCreditAggregates(DateTime startDate, DateTime endDate, String groupBy) {
        return walletAvailable ? aggregatesToReturn : new List<WalletAggregateDTO>();
    }

    public List<WalletAggregateDTO> getFlexCreditByPrompt(DateTime startDate, DateTime endDate) {
        return walletAvailable ? byPromptToReturn : new List<WalletAggregateDTO>();
    }

    public List<WalletAggregateDTO> getFlexCreditByUser(DateTime startDate, DateTime endDate) {
        return walletAvailable ? byUserToReturn : new List<WalletAggregateDTO>();
    }

    public List<WalletAggregateDTO> getFlexCreditByCustomTag(DateTime startDate, DateTime endDate) {
        return walletAvailable ? byCustomTagToReturn : new List<WalletAggregateDTO>();
    }
}
