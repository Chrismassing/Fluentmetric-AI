/**
 * Agentforce invocable: returns 8-week WoW deltas (requests, users, tokens)
 * plus the latest-vs-prior pct-point deltas as labels for direct rendering by
 * the agent. Used by the `adoption_health` topic to answer "is usage growing
 * week over week?".
 *
 * The full 8-week series is serialized to JSON so the agent can pick out
 * specific weeks; the latest deltas are surfaced as scalar string labels for
 * clean inline rendering.
 */
public with sharing class GetAdoptionDeltasAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
    }

    public class Response {
        @InvocableVariable(
            label='Latest requests WoW pct label'
            description='Latest week vs prior week request volume change, e.g. "+12.5%".'
        )
        public String latestRequestsWowPctLabel;
        @InvocableVariable(label='Latest users WoW pct label')
        public String latestUsersWowPctLabel;
        @InvocableVariable(label='Latest tokens WoW pct label')
        public String latestTokensWowPctLabel;
        @InvocableVariable(
            label='Latest week ISO label'
            description='ISO 8601 week label for the most recent week, e.g. "2026-W22".'
        )
        public String latestWeekIsoLabel;
        @InvocableVariable(label='Prior week ISO label')
        public String priorWeekIsoLabel;
        @InvocableVariable(
            label='Weeks JSON'
            description='JSON array of 8 weekly objects: {weekIsoLabel, requests, activeUsers, tokens, requestsWowPct, usersWowPct, tokensWowPct}.'
        )
        public String weeksJson;
    }

    @InvocableMethod(
        label='Get GenAI Adoption Deltas'
        description='Returns trailing 8-week trend data (requests, active users, tokens) with week-over-week percentage deltas.'
        category='FluentMetric AI Tableau Next'
    )
    public static List<Response> run(List<Request> requests) {
        AiInsightsService svc = serviceOverride == null ? new AiInsightsService() : serviceOverride;
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            try {
                DateRangeFilter filter = new DateRangeFilter();
                filter.startDate = r.startDate == null ? Datetime.now().addDays(-30) : r.startDate;
                filter.endDate = r.endDate == null ? Datetime.now() : r.endDate;
                OrgAdoptionDeltasDTO dto = svc.getOrgAdoptionDeltas(filter);
                resp.latestRequestsWowPctLabel = formatPct(dto.latestRequestsWowPct);
                resp.latestUsersWowPctLabel = formatPct(dto.latestUsersWowPct);
                resp.latestTokensWowPctLabel = formatPct(dto.latestTokensWowPct);
                if (dto.weeks != null && dto.weeks.size() >= 2) {
                    resp.latestWeekIsoLabel = dto.weeks[dto.weeks.size() - 1].weekIsoLabel;
                    resp.priorWeekIsoLabel = dto.weeks[dto.weeks.size() - 2].weekIsoLabel;
                }
                resp.weeksJson = JSON.serialize(dto.weeks == null ? new List<Object>() : dto.weeks);
            } catch (Exception e) {
                resp.weeksJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
            }
            out.add(resp);
        }
        return out;
    }

    private static String formatPct(Decimal pct) {
        if (pct == null) {
            return '0%';
        }
        String prefix = pct >= 0 ? '+' : '';
        return prefix + pct.setScale(1) + '%';
    }
}
