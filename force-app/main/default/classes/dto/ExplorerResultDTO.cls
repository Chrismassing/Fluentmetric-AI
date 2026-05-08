/**
 * One row of the Explorer pivot result. metricValue is the numeric answer
 * for whichever metric was selected; metricLabel is its human-readable form.
 */
public with sharing class ExplorerResultDTO {
    @AuraEnabled
    public String groupKey;
    @AuraEnabled
    public String groupLabel;
    @AuraEnabled
    public Decimal metricValue;
    @AuraEnabled
    public String metricLabel;
    @AuraEnabled
    public Integer supportingCount;

    public ExplorerResultDTO() {
        this.metricValue = 0;
        this.supportingCount = 0;
    }

    public ExplorerResultDTO(String groupKey, String groupLabel, Decimal metricValue) {
        this.groupKey = groupKey;
        this.groupLabel = groupLabel;
        this.metricValue = metricValue;
        this.supportingCount = 0;
    }
}
