/**
 * Cohort retention rollup: each row is one ISO-week cohort (users whose first
 * observed GenAI request landed in that week) plus a per-age-week retention
 * series (`retentionByWeek[0]` is week 0 — always 1.0 by definition; each
 * subsequent index is the share of the cohort that was active that many weeks
 * later).
 *
 * Renderers: `aiInsightsCohortHeatmap` LWC. The heatmap caps the series at 26
 * weeks (`MAX_COHORT_WEEKS`) to bound heap and avoid sparse trailing rows.
 *
 * `truncated = true` when the underlying DAO call (`getRequestTimestampsByUser`)
 * hit the 50k row cap — the LWC surfaces a banner so users know to narrow the
 * date range.
 */
public with sharing class AdoptionCohortsDTO {
    public static final Integer MAX_COHORT_WEEKS = 26;

    @AuraEnabled
    public List<CohortRow> cohorts;
    @AuraEnabled
    public Boolean truncated;
    @AuraEnabled
    public Integer totalUsersObserved;

    public AdoptionCohortsDTO() {
        this.cohorts = new List<CohortRow>();
        this.truncated = false;
        this.totalUsersObserved = 0;
    }

    public class CohortRow {
        @AuraEnabled
        public String weekIsoLabel;
        @AuraEnabled
        public Date weekStart;
        @AuraEnabled
        public Integer cohortSize;
        @AuraEnabled
        public Integer ageInWeeks;
        @AuraEnabled
        public List<Decimal> retentionByWeek;

        public CohortRow() {
            this.cohortSize = 0;
            this.ageInWeeks = 0;
            this.retentionByWeek = new List<Decimal>();
        }
    }
}
