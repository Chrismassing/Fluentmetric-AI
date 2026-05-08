/**
 * Summary for the Safety & Trust dashboard.
 * avgCategoryScores: category name → average score (0-1).
 * flaggedByCategory: category name → count flagged above threshold.
 */
public with sharing class ContentSafetyDTO {
    @AuraEnabled
    public Integer totalGenerations;
    @AuraEnabled
    public Integer toxicCount;
    @AuraEnabled
    public Decimal toxicRate;
    @AuraEnabled
    public Map<String, Decimal> avgCategoryScores;
    @AuraEnabled
    public Map<String, Integer> flaggedByCategory;
    @AuraEnabled
    public List<PromptOutputDTO> recentFlaggedOutputs;

    public ContentSafetyDTO() {
        this.totalGenerations = 0;
        this.toxicCount = 0;
        this.toxicRate = 0;
        this.avgCategoryScores = new Map<String, Decimal>();
        this.flaggedByCategory = new Map<String, Integer>();
        this.recentFlaggedOutputs = new List<PromptOutputDTO>();
    }
}
