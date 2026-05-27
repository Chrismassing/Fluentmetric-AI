/**
 * Trailing 8-week trend of (requests, activeUsers, tokens) for the Overview
 * tab's WoW chip strip and the Activity tab's adoption sparkline.
 *
 * weeks[0] is the OLDEST week, weeks[size-1] is the most recent (i.e. the
 * current/active week). Same-week-prior comparisons are computed by the
 * service so the LWC never has to do date math.
 *
 * `latestWoW*Pct` fields are pct-point deltas (latest week vs. prior week),
 * already rounded to 2 dp. They're exposed separately so the KPI chip can
 * render without scanning the series.
 */
public with sharing class OrgAdoptionDeltasDTO {
    @AuraEnabled
    public List<WeekDelta> weeks;
    @AuraEnabled
    public Decimal latestRequestsWowPct;
    @AuraEnabled
    public Decimal latestUsersWowPct;
    @AuraEnabled
    public Decimal latestTokensWowPct;

    public OrgAdoptionDeltasDTO() {
        this.weeks = new List<WeekDelta>();
        this.latestRequestsWowPct = 0;
        this.latestUsersWowPct = 0;
        this.latestTokensWowPct = 0;
    }

    public class WeekDelta {
        @AuraEnabled
        public Date weekStart;
        @AuraEnabled
        public String weekIsoLabel;
        @AuraEnabled
        public Integer requests;
        @AuraEnabled
        public Integer activeUsers;
        @AuraEnabled
        public Long tokens;
        @AuraEnabled
        public Decimal requestsWowPct;
        @AuraEnabled
        public Decimal usersWowPct;
        @AuraEnabled
        public Decimal tokensWowPct;

        public WeekDelta() {
            this.requests = 0;
            this.activeUsers = 0;
            this.tokens = 0L;
            this.requestsWowPct = 0;
            this.usersWowPct = 0;
            this.tokensWowPct = 0;
        }
    }
}
