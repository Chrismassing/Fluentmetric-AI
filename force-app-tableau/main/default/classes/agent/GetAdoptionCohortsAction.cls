/**
 * Agentforce invocable: returns ISO-week cohort retention for the
 * `cohorts` topic. The DTO already caps each cohort row at 26 age-weeks,
 * but the action enforces an additional cohort-row cap so the JSON payload
 * stays under the agent's safe context budget.
 */
public with sharing class GetAdoptionCohortsAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static final Integer COHORT_ROW_CAP = 26;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
    }

    public class Response {
        @InvocableVariable(
            label='Cohorts JSON'
            description='JSON array of {weekIsoLabel, weekStart, cohortSize, ageInWeeks, retentionByWeek[]}. Capped at 26 rows.'
        )
        public String cohortsJson;
        @InvocableVariable(
            label='Truncated'
            description='True when the underlying timestamp DAO call hit its 50k cap — agent should advise narrowing the window.'
        )
        public Boolean truncated;
        @InvocableVariable(label='Total users observed')
        public Integer totalUsersObserved;
    }

    @InvocableMethod(
        label='Get GenAI Adoption Cohorts'
        description='Returns ISO-week cohort retention rows for the most recent 26 cohorts, with per-week retention percentages.'
        category='FluentMetric AI Tableau Next'
    )
    public static List<Response> run(List<Request> requests) {
        AiInsightsService svc = serviceOverride == null ? new AiInsightsService() : serviceOverride;
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            try {
                DateRangeFilter filter = new DateRangeFilter();
                filter.startDate = r.startDate == null ? Datetime.now().addDays(-180) : r.startDate;
                filter.endDate = r.endDate == null ? Datetime.now() : r.endDate;
                AdoptionCohortsDTO dto = svc.getAdoptionCohorts(filter);
                resp.truncated = dto.truncated;
                resp.totalUsersObserved = dto.totalUsersObserved;

                List<AdoptionCohortsDTO.CohortRow> rows = dto.cohorts == null
                    ? new List<AdoptionCohortsDTO.CohortRow>()
                    : dto.cohorts;
                if (rows.size() > COHORT_ROW_CAP) {
                    // Slice the most recent 26 cohorts (DTO sorts ASC).
                    List<AdoptionCohortsDTO.CohortRow> tail = new List<AdoptionCohortsDTO.CohortRow>();
                    Integer start = rows.size() - COHORT_ROW_CAP;
                    for (Integer i = start; i < rows.size(); i++) {
                        tail.add(rows[i]);
                    }
                    rows = tail;
                }
                resp.cohortsJson = JSON.serialize(rows);
            } catch (Exception e) {
                resp.cohortsJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
                resp.truncated = false;
                resp.totalUsersObserved = 0;
            }
            out.add(resp);
        }
        return out;
    }
}
