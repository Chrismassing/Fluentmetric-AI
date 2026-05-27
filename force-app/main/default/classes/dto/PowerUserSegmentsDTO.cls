/**
 * Pareto-style power-user segmentation. The service sorts the existing
 * per-user aggregate by request count DESC, slices the top-1% / top-10%
 * cohorts, and computes how much of total volume those slices drive.
 *
 * Used by the Overview tab Pareto chip ("Top 10% drive XX% of volume") and
 * by the User Adoption table tier badges. Re-uses already-paid-for data —
 * no extra DAO call.
 *
 * topUsers carries up to 50 of the heaviest users so the LWC can show a
 * tooltip / quick-jump list without another call.
 */
public with sharing class PowerUserSegmentsDTO {
    @AuraEnabled
    public Integer totalActiveUsers;
    @AuraEnabled
    public Long totalRequests;

    // Top-10% segment
    @AuraEnabled
    public Integer top10PercentUserCount;
    @AuraEnabled
    public Long top10PercentRequestCount;
    @AuraEnabled
    public Decimal top10PercentVolumeShare;

    // Top-1% segment (often empty in small orgs)
    @AuraEnabled
    public Integer top1PercentUserCount;
    @AuraEnabled
    public Long top1PercentRequestCount;
    @AuraEnabled
    public Decimal top1PercentVolumeShare;

    @AuraEnabled
    public List<TopUser> topUsers;

    public PowerUserSegmentsDTO() {
        this.totalActiveUsers = 0;
        this.totalRequests = 0L;
        this.top10PercentUserCount = 0;
        this.top10PercentRequestCount = 0L;
        this.top10PercentVolumeShare = 0;
        this.top1PercentUserCount = 0;
        this.top1PercentRequestCount = 0L;
        this.top1PercentVolumeShare = 0;
        this.topUsers = new List<TopUser>();
    }

    public class TopUser {
        @AuraEnabled
        public String userId;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public Integer requestCount;
        @AuraEnabled
        public Long totalTokens;
        @AuraEnabled
        public String tier;

        public TopUser() {
            this.requestCount = 0;
            this.totalTokens = 0L;
        }
    }
}
