/**
 * Side-channel trends DTO for the Overview KPI strip.
 *
 * Returned by AiInsightsController.getOverviewTrends — kept separate from
 * UsageOverviewDTO so the main (cached) Overview query stays unchanged and
 * trend rendering can fail independently without hiding the KPIs.
 *
 * previousXxx fields are the SAME aggregates as UsageOverviewDTO, but over a
 * prior window of equal length immediately preceding the main one. The LWC
 * uses these to render a +% / −% badge below each primary card.
 *
 * `daily*Series` are day-granularity numeric series sized `series.length ==
 * numberOfDaysInMainWindow`, index 0 = earliest day. The LWC draws them as
 * inline SVG polylines (sparklines) — no charting library.
 *
 * All numeric fields default to zero so the LWC can always read them
 * without null-guards.
 */
public with sharing class OverviewTrendsDTO {
    // Prior-window totals (same definitions as UsageOverviewDTO).
    @AuraEnabled
    public Integer previousTotalRequests;
    @AuraEnabled
    public Integer previousUniqueUsers;
    @AuraEnabled
    public Decimal previousAcceptanceRate;
    @AuraEnabled
    public Long previousTotalTokens;
    @AuraEnabled
    public Integer previousFeedbackCount;
    @AuraEnabled
    public Integer previousToxicFlagCount;

    // Daily sparkline series — one entry per day in the main window,
    // oldest first. Length matches `daysInWindow`.
    @AuraEnabled
    public Integer daysInWindow;
    @AuraEnabled
    public List<Integer> dailyRequests;
    @AuraEnabled
    public List<Long> dailyTokens;
    @AuraEnabled
    public List<Integer> dailyToxicFlags;

    public OverviewTrendsDTO() {
        this.previousTotalRequests = 0;
        this.previousUniqueUsers = 0;
        this.previousAcceptanceRate = 0;
        this.previousTotalTokens = 0L;
        this.previousFeedbackCount = 0;
        this.previousToxicFlagCount = 0;
        this.daysInWindow = 0;
        this.dailyRequests = new List<Integer>();
        this.dailyTokens = new List<Long>();
        this.dailyToxicFlags = new List<Integer>();
    }
}
