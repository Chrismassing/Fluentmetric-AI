/**
 * Imports a Salesforce Flex Credits Rate Card PDF and applies the parsed
 * multipliers to FluentMetric_Cost_Settings__c so non-Wallet orgs can keep
 * their estimates current without hand-editing custom-setting fields.
 *
 * Flow:
 *   1. Admin uploads the PDF — the LWC creates a ContentVersion.
 *   2. parseUpload(contentVersionId) loads the file, asks the configured
 *      LLM adapter to return strict JSON of the 8 multiplier values, and
 *      hands back a ParsedRateCard + a diff against the current settings.
 *   3. applyDiff(...) writes the new values, inserts a RateCardUpload__c
 *      audit record, and resets the CostCalculatorService settings cache
 *      so the next callback in the same transaction sees the new numbers.
 *   4. revert(...) restores the captured prior values from the audit
 *      record's ChangeSummary__c.
 *
 * The LLM call is encapsulated behind ILlmAdapter so tests can inject a
 * mock without touching ConnectApi. NEVER throws raw exceptions — every
 * public method either returns a value or throws an AuraHandledException
 * with a user-friendly message.
 */
public with sharing class RateCardImportService {
    @TestVisible
    private static ILlmAdapter adapterOverride;

    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_APPLIED = 'Applied';
    private static final String STATUS_REVERTED = 'Reverted';

    private static final Map<String, String> JSON_KEY_TO_FIELD = new Map<String, String>{
        'standard_action' => 'Action_Flat_FC__c',
        'custom_action' => 'Custom_Action_FC__c',
        'standard_voice_action' => 'Standard_Voice_Action_FC__c',
        'custom_voice_action' => 'Custom_Voice_Action_FC__c',
        'starter_prompt' => 'Tier_Starter_FC__c',
        'basic_prompt' => 'Tier_Basic_FC__c',
        'standard_prompt' => 'Tier_Standard_FC__c',
        'advanced_prompt' => 'Tier_Advanced_FC__c'
    };

    /** DTO surfaced to the LWC after parse. */
    public class ParseResult {
        @AuraEnabled
        public ParsedRateCard parsed;
        @AuraEnabled
        public List<DiffEntry> diff;

        public ParseResult(ParsedRateCard parsed, List<DiffEntry> diff) {
            this.parsed = parsed;
            this.diff = diff;
        }
    }

    public class ParsedRateCard {
        @AuraEnabled
        public String effectiveDate;
        @AuraEnabled
        public Map<String, Decimal> multipliers;
        @AuraEnabled
        public String rawJson;
    }

    public class DiffEntry {
        @AuraEnabled
        public String field;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Decimal currentValue;
        @AuraEnabled
        public Decimal newValue;
        @AuraEnabled
        public Boolean willChange;

        public DiffEntry(String field, String label, Decimal currentValue, Decimal newValue) {
            this.field = field;
            this.label = label;
            this.currentValue = currentValue;
            this.newValue = newValue;
            this.willChange = currentValue != newValue;
        }
    }

    /** Pluggable LLM adapter — production calls Einstein, tests inject a fake. */
    public interface ILlmAdapter {
        String extractRateCardJson(Blob pdfBlob, String fileName);
    }

    // ───────────────────────── Public API ─────────────────────────

    public ParseResult parseUpload(Id contentVersionId) {
        if (contentVersionId == null) {
            throw error('Content Version Id is required');
        }
        ContentVersion cv = loadContentVersion(contentVersionId);
        ParsedRateCard parsed = invokeLlm(cv);
        List<DiffEntry> diff = buildDiff(parsed);
        return new ParseResult(parsed, diff);
    }

    public Id applyParsedUpload(Id contentVersionId, String parsedJson, String notes) {
        if (String.isBlank(parsedJson)) {
            throw error('Parsed payload is required');
        }
        ParsedRateCard parsed;
        try {
            parsed = (ParsedRateCard) JSON.deserialize(parsedJson, ParsedRateCard.class);
        } catch (Exception ex) {
            throw error('Parsed payload is not valid JSON');
        }
        if (parsed == null || parsed.multipliers == null || parsed.multipliers.isEmpty()) {
            throw error('Parsed payload is missing multipliers');
        }

        FluentMetric_Cost_Settings__c current = FluentMetric_Cost_Settings__c.getOrgDefaults();
        if (current == null) {
            current = new FluentMetric_Cost_Settings__c();
        }
        List<DiffEntry> diff = buildDiffFromMultipliers(parsed.multipliers, current);
        applyMultipliers(parsed.multipliers, current);

        upsertSetting(current);

        RateCardUpload__c audit = new RateCardUpload__c();
        audit.ContentDocumentId__c = resolveContentDocumentId(contentVersionId);
        audit.ParsedJson__c = parsedJson;
        audit.EffectiveDate__c = parseDate(parsed.effectiveDate);
        audit.AppliedBy__c = UserInfo.getUserId();
        audit.Status__c = STATUS_APPLIED;
        audit.ChangeSummary__c = JSON.serialize(diff);
        audit.Notes__c = notes;
        insert audit;

        CostCalculatorService.resetSettingsCacheForRefresh();
        return audit.Id;
    }

    public Id revert(Id rateCardUploadId) {
        if (rateCardUploadId == null) {
            throw error('Rate Card Upload Id is required');
        }
        List<RateCardUpload__c> existing = [
            SELECT Id, Status__c, ChangeSummary__c
            FROM RateCardUpload__c
            WHERE Id = :rateCardUploadId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw error('Rate card upload not found');
        }
        RateCardUpload__c row = existing[0];
        if (row.Status__c != STATUS_APPLIED) {
            throw error('Only Applied uploads can be reverted');
        }
        if (String.isBlank(row.ChangeSummary__c)) {
            throw error('Change summary missing — cannot revert');
        }

        List<DiffEntry> entries;
        try {
            entries = (List<DiffEntry>) JSON.deserialize(row.ChangeSummary__c, List<DiffEntry>.class);
        } catch (Exception ex) {
            throw error('Change summary is corrupt — cannot revert');
        }

        FluentMetric_Cost_Settings__c current = FluentMetric_Cost_Settings__c.getOrgDefaults();
        if (current == null) {
            current = new FluentMetric_Cost_Settings__c();
        }
        for (DiffEntry e : entries) {
            if (String.isNotBlank(e.field)) {
                current.put(e.field, e.currentValue);
            }
        }
        upsertSetting(current);

        row.Status__c = STATUS_REVERTED;
        update row;

        CostCalculatorService.resetSettingsCacheForRefresh();
        return row.Id;
    }

    public List<RateCardUpload__c> listRecent(Integer limitN) {
        Integer cap = (limitN == null || limitN <= 0 || limitN > 50) ? 10 : limitN;
        return [
            SELECT Id, Name, Status__c, EffectiveDate__c, AppliedBy__c, AppliedBy__r.Name, Notes__c, CreatedDate
            FROM RateCardUpload__c
            ORDER BY CreatedDate DESC
            LIMIT :cap
        ];
    }

    // ───────────────────────── Internals ─────────────────────────

    private ContentVersion loadContentVersion(Id contentVersionId) {
        List<ContentVersion> rows = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw error('Uploaded file not found');
        }
        return rows[0];
    }

    private String resolveContentDocumentId(Id contentVersionId) {
        if (contentVersionId == null) {
            return null;
        }
        try {
            ContentVersion cv = loadContentVersion(contentVersionId);
            return cv.ContentDocumentId;
        } catch (Exception ex) {
            return null;
        }
    }

    private ParsedRateCard invokeLlm(ContentVersion cv) {
        ILlmAdapter adapter = adapterOverride == null ? new EinsteinLlmAdapter() : adapterOverride;
        // Note: Apex is case-insensitive — naming this `json` would shadow
        // the `JSON` system class, breaking `JSON.deserializeUntyped` below.
        String rawPayload;
        try {
            rawPayload = adapter.extractRateCardJson(cv.VersionData, cv.Title);
        } catch (Exception ex) {
            throw error('Could not parse the uploaded rate card. Try re-uploading the official Salesforce PDF.');
        }
        if (String.isBlank(rawPayload)) {
            throw error('Empty response from rate-card parser');
        }

        ParsedRateCard parsed = new ParsedRateCard();
        parsed.rawJson = rawPayload;
        parsed.multipliers = new Map<String, Decimal>();

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(rawPayload);
            Object effDate = root.get('effective_date');
            parsed.effectiveDate = effDate == null ? null : String.valueOf(effDate);

            Object mults = root.get('multipliers');
            if (mults instanceof Map<String, Object>) {
                Map<String, Object> mm = (Map<String, Object>) mults;
                for (String key : JSON_KEY_TO_FIELD.keySet()) {
                    Object v = mm.get(key);
                    if (v != null) {
                        parsed.multipliers.put(key, toDecimal(v));
                    }
                }
            }
        } catch (Exception ex) {
            throw error('Rate-card parser returned invalid JSON');
        }

        if (parsed.multipliers.isEmpty()) {
            throw error('Rate-card parser returned no multipliers');
        }
        return parsed;
    }

    private List<DiffEntry> buildDiff(ParsedRateCard parsed) {
        FluentMetric_Cost_Settings__c current = FluentMetric_Cost_Settings__c.getOrgDefaults();
        if (current == null) {
            current = new FluentMetric_Cost_Settings__c();
        }
        return buildDiffFromMultipliers(parsed.multipliers, current);
    }

    private List<DiffEntry> buildDiffFromMultipliers(
        Map<String, Decimal> multipliers,
        FluentMetric_Cost_Settings__c current
    ) {
        List<DiffEntry> out = new List<DiffEntry>();
        for (String key : JSON_KEY_TO_FIELD.keySet()) {
            String field = JSON_KEY_TO_FIELD.get(key);
            Decimal newVal = multipliers.get(key);
            if (newVal == null) {
                continue;
            }
            Decimal curVal = (Decimal) current.get(field);
            out.add(new DiffEntry(field, key, curVal, newVal));
        }
        return out;
    }

    private void applyMultipliers(Map<String, Decimal> multipliers, FluentMetric_Cost_Settings__c row) {
        for (String key : JSON_KEY_TO_FIELD.keySet()) {
            Decimal v = multipliers.get(key);
            if (v != null) {
                row.put(JSON_KEY_TO_FIELD.get(key), v);
            }
        }
    }

    private void upsertSetting(FluentMetric_Cost_Settings__c row) {
        if (row.SetupOwnerId == null) {
            row.SetupOwnerId = UserInfo.getOrganizationId();
        }
        upsert row;
    }

    private static Decimal toDecimal(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Decimal) {
            return (Decimal) v;
        }
        if (v instanceof Integer) {
            return Decimal.valueOf((Integer) v);
        }
        if (v instanceof Long) {
            return Decimal.valueOf((Long) v);
        }
        if (v instanceof Double) {
            return Decimal.valueOf((Double) v);
        }
        try {
            return Decimal.valueOf(String.valueOf(v));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date parseDate(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            return Date.valueOf(iso);
        } catch (Exception ex) {
            return null;
        }
    }

    private static AuraHandledException error(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }

    /**
     * Production adapter — calls ConnectApi.EinsteinLLM with the PDF binary
     * and a strict-JSON system prompt. Wrapped in try/catch so transient
     * Einstein errors surface as a user-friendly message rather than a stack.
     */
    /**
     * Strict-JSON system prompt for the rate-card extractor. Lives on the
     * outer class because Apex disallows `static` fields on inner classes.
     */
    private static final String EINSTEIN_SYSTEM_PROMPT =
        'You are a strict data extractor. The user will provide the official Salesforce ' +
        'Flex Credits Rate Card. Return ONLY a JSON object — no prose, no code fence — ' +
        'matching exactly:\n' +
        '{\n' +
        '  "effective_date": "YYYY-MM-DD",\n' +
        '  "multipliers": {\n' +
        '    "standard_action": <number>, "custom_action": <number>,\n' +
        '    "standard_voice_action": <number>, "custom_voice_action": <number>,\n' +
        '    "starter_prompt": <number>, "basic_prompt": <number>,\n' +
        '    "standard_prompt": <number>, "advanced_prompt": <number>\n' +
        '  }\n' +
        '}\n' +
        'Use the Production Environment column values. If a value is missing, omit that key.';

    /**
     * Production adapter — calls ConnectApi.EinsteinLLM with the PDF binary
     * and a strict-JSON system prompt. Wrapped in try/catch so transient
     * Einstein errors surface as a user-friendly message rather than a stack.
     * Tests bypass this by injecting their own ILlmAdapter via adapterOverride.
     */
    public class EinsteinLlmAdapter implements ILlmAdapter {
        public String extractRateCardJson(Blob pdfBlob, String fileName) {
            String pdfText = pdfBlob == null ? '' : safeToString(pdfBlob);
            if (String.isBlank(pdfText)) {
                throw new IllegalArgumentException('Empty file');
            }
            String userPrompt =
                'File: ' +
                (fileName == null ? 'rate_card.pdf' : fileName) +
                '\n\n--- BEGIN RATE CARD ---\n' +
                pdfText +
                '\n--- END RATE CARD ---';
            return callEinstein(EINSTEIN_SYSTEM_PROMPT, userPrompt);
        }

        private String safeToString(Blob b) {
            try {
                return b.toString();
            } catch (Exception ex) {
                // Binary PDFs can't always be UTF-8 decoded; fall back to base64
                // so the LLM at least sees structured payload it can refuse.
                return EncodingUtil.base64Encode(b);
            }
        }

        private String callEinstein(String systemPrompt, String userPrompt) {
            // ConnectApi.EinsteinLLM invocation belongs here. The exact
            // signature is API-version-dependent; v62 supports
            // ConnectApi.EinsteinLLM.generateMessages(req) with a
            // ConnectApi.EinsteinLLMGenerationsInput payload. Implement at
            // deploy time once the target org's Einstein entitlement is
            // confirmed. Until then, this throws so the caller surfaces the
            // friendly error from the service layer.
            throw new CalloutException(
                'Einstein adapter not yet wired for this org. Configure ConnectApi.EinsteinLLM in RateCardImportService.EinsteinLlmAdapter.callEinstein.'
            );
        }
    }
}
