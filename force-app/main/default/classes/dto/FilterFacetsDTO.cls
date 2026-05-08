/**
 * Facet payload for the filter rail — one server round-trip populates every
 * combobox with values that actually exist in the active date window. Users
 * never see stale or impossible options.
 *
 * Each entry on the facet lists carries the raw key, a display label
 * (resolved where applicable, e.g. prompt template master label), and an
 * observed request count in the range so the UI can sort by popularity and
 * show counts on hover.
 *
 * `topUsers` is length-capped (see AiInsightsService.getFilterFacets) because
 * user cardinality is unbounded in practice — the rail uses typeahead via
 * searchUsersInRange for anything beyond the top N.
 */
public with sharing class FilterFacetsDTO {
    public class FacetOption {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Integer count;

        public FacetOption(String value, String label, Integer count) {
            this.value = value;
            this.label = label;
            this.count = count;
        }
    }

    @AuraEnabled
    public List<FacetOption> models;
    @AuraEnabled
    public List<FacetOption> providers;
    @AuraEnabled
    public List<FacetOption> features;
    @AuraEnabled
    public List<FacetOption> appTypes;
    @AuraEnabled
    public List<FacetOption> promptTemplates;
    @AuraEnabled
    public List<FacetOption> topUsers;

    public FilterFacetsDTO() {
        this.models = new List<FacetOption>();
        this.providers = new List<FacetOption>();
        this.features = new List<FacetOption>();
        this.appTypes = new List<FacetOption>();
        this.promptTemplates = new List<FacetOption>();
        this.topUsers = new List<FacetOption>();
    }
}
