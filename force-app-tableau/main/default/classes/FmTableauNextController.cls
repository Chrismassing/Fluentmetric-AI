/**
 * @AuraEnabled facade for the Tableau Next edition LWCs (fmTableauNextLauncher,
 * fmTableauKpiTile, fmTableauAgentChat).
 *
 * Tableau Next dashboards live in the Tableau Einstein app and are opened via
 * a deep-link from Salesforce. This controller does NOT query Tableau Next —
 * it queries the same Data Cloud DMOs the Lightning edition reads, surfacing
 * top-of-funnel KPIs in a tile that lives next to the launcher button.
 *
 * Depends on the Lightning edition (force-app/) for AiInsightsService, DTOs,
 * and DAO. Both editions share `force-app-tableau` Apex classes via the
 * `FluentMetric AI` package dependency declared in sfdx-project.json.
 */
public with sharing class FmTableauNextController {
    @TestVisible
    private static AiInsightsService serviceOverride;

    private static AiInsightsService service() {
        return serviceOverride == null ? new AiInsightsService() : serviceOverride;
    }

    /**
     * Top-line KPIs for the home page tile: total requests, unique users,
     * acceptance rate, total tokens. Cached because the underlying service
     * already caches expensive aggregates and the tile is read-only.
     */
    @AuraEnabled(cacheable=true)
    public static UsageOverviewDTO getKpiSummary(DateTime startDate, DateTime endDate) {
        try {
            DateRangeFilter filter = new DateRangeFilter();
            filter.startDate = startDate == null ? Datetime.now().addDays(-30) : startDate;
            filter.endDate = endDate == null ? Datetime.now() : endDate;
            return service().getOverview(filter);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load KPI summary: ' + e.getMessage());
        }
    }

    /**
     * Returns the deep-link URL the launcher button navigates to. Resolves
     * to the AnalyticsWorkspace record-page URL so the user lands directly
     * on the FluentMetric_AI workspace's dashboard list. Falls back to the
     * generic Tableau Next app tab if the workspace is missing (e.g. the
     * customer hasn't deployed it yet).
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getLauncherTarget() {
        String path;
        List<AnalyticsWorkspace> ws = [
            SELECT Id
            FROM AnalyticsWorkspace
            WHERE DeveloperName = 'FluentMetric_AI_Workspace'
            LIMIT 1
        ];
        if (!ws.isEmpty()) {
            path = '/lightning/r/AnalyticsWorkspace/' + ws[0].Id + '/view';
        } else {
            path = System.Label.FM_TBL_Launcher_Workspace_Path;
        }
        return new Map<String, String>{
            'workspaceLabel' => System.Label.FM_TBL_Launcher_Workspace_Label,
            'workspacePath' => path
        };
    }
}
