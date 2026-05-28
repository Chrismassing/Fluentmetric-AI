/**
 * Agentforce invocable: returns Pareto-style power-user segmentation —
 * top-1% / top-10% volume share plus the heaviest 25 users with names and
 * tier badges. Used by the `adoption_health` topic to answer
 * "who are my power users?".
 */
public with sharing class GetPowerUserSegmentsAction {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static final Integer TOP_USERS_CAP = 25;

    public class Request {
        @InvocableVariable(label='Start date')
        public Datetime startDate;
        @InvocableVariable(label='End date')
        public Datetime endDate;
    }

    public class Response {
        @InvocableVariable(
            label='Top 1% volume share label'
            description='Share of total volume driven by the top 1%, e.g. "23%".'
        )
        public String top1PercentVolumeShareLabel;
        @InvocableVariable(label='Top 10% volume share label')
        public String top10PercentVolumeShareLabel;
        @InvocableVariable(label='Top 1% user count')
        public Integer top1PercentUserCount;
        @InvocableVariable(label='Top 10% user count')
        public Integer top10PercentUserCount;
        @InvocableVariable(
            label='Top users JSON'
            description='JSON array of up to 25 heaviest users: {userId, userName, requestCount, totalTokens, tier}.'
        )
        public String topUsersJson;
    }

    @InvocableMethod(
        label='Get GenAI Power User Segments'
        description='Returns top-1% / top-10% volume share, user counts, and the top 25 heaviest users with names and tier labels.'
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
                PowerUserSegmentsDTO dto = svc.getPowerUserSegments(filter);
                resp.top1PercentVolumeShareLabel = formatRate(dto.top1PercentVolumeShare);
                resp.top10PercentVolumeShareLabel = formatRate(dto.top10PercentVolumeShare);
                resp.top1PercentUserCount = dto.top1PercentUserCount;
                resp.top10PercentUserCount = dto.top10PercentUserCount;

                List<PowerUserSegmentsDTO.TopUser> topUsers = dto.topUsers == null
                    ? new List<PowerUserSegmentsDTO.TopUser>()
                    : dto.topUsers;
                if (topUsers.size() > TOP_USERS_CAP) {
                    List<PowerUserSegmentsDTO.TopUser> trimmed = new List<PowerUserSegmentsDTO.TopUser>();
                    for (Integer i = 0; i < TOP_USERS_CAP; i++) {
                        trimmed.add(topUsers[i]);
                    }
                    topUsers = trimmed;
                }
                resp.topUsersJson = JSON.serialize(topUsers);
            } catch (Exception e) {
                resp.topUsersJson = JSON.serialize(
                    new Map<String, Object>{ 'error' => true, 'message' => e.getMessage() }
                );
            }
            out.add(resp);
        }
        return out;
    }

    private static String formatRate(Decimal rate) {
        if (rate == null) {
            return null;
        }
        Integer pct = Integer.valueOf(Math.round(rate * 100));
        return pct + '%';
    }
}
