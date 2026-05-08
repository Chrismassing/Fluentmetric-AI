/**
 * Single request/output pair for the Output Viewer. inputPrompt and
 * generatedText are truncated for list view; the full text is fetched lazily.
 */
public with sharing class PromptOutputDTO {
    @AuraEnabled
    public String requestId;
    @AuraEnabled
    public String userName;
    @AuraEnabled
    public DateTime requestDate;
    // inputPrompt / generatedText are truncated to ~280 chars for inline
    // list-view rendering. inputPromptFull / generatedTextFull carry the
    // complete payload so the Expand modal can show the full text.
    @AuraEnabled
    public String inputPrompt;
    @AuraEnabled
    public String generatedText;
    @AuraEnabled
    public String inputPromptFull;
    @AuraEnabled
    public String generatedTextFull;
    @AuraEnabled
    public String feedbackValue;
    @AuraEnabled
    public Boolean isToxic;
    @AuraEnabled
    public Integer inputTokens;
    @AuraEnabled
    public Integer outputTokens;
    @AuraEnabled
    public String model;

    public PromptOutputDTO() {
        this.isToxic = false;
        this.inputTokens = 0;
        this.outputTokens = 0;
    }
}
