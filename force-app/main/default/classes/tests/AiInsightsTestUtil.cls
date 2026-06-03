/**
 * Fixture helpers for tests that need DMO SObject rows or
 * AggregateResult instances.
 *
 * DMO SObject types (GenAIGatewayRequest__dlm and friends) are not in
 * `Schema.getGlobalDescribe()` in Apex test context, so callers cannot
 * use `newSObject()` against them. They ARE resolvable via
 * `Type.forName(...)`, and `System.JSON.deserialize` accepts that Type
 * and produces a populated read-only DMO SObject the service can read
 * with `.get('camelCaseField__c')`. Verified live on cvk-dev.
 *
 * AggregateResult cannot be JSON-deserialized with arbitrary aliases
 * ("Invalid field cnt for AggregateResult"). Instead we run a real
 * `[SELECT COUNT(Id) alias FROM User WHERE Id = :seededId]` against a
 * stable User row and bucket the resulting AggregateResult into a Map
 * the test can index by group key.
 */
@IsTest
public class AiInsightsTestUtil {
    private static final String DEFAULT_USER_ID = '005000000000001';
    private static final String DEFAULT_PROMPT = 'Atlas__P1';
    private static final String DEFAULT_MODEL = 'gpt-4';
    private static final String DEFAULT_FEATURE = 'EinsteinForFlow';

    // ── DMO row builders ───────────────────────────────────────────────────

    public static SObject makeRequest(
        String gatewayRequestId,
        String userId,
        String promptDevName,
        String model,
        String feature,
        DateTime ts,
        Decimal promptTokens,
        Decimal completionTokens
    ) {
        Decimal pt = promptTokens == null ? 0 : promptTokens;
        Decimal ct = completionTokens == null ? 0 : completionTokens;
        Map<String, Object> body = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => 'GenAIGatewayRequest__dlm' },
            'gatewayRequestId__c' => gatewayRequestId,
            'userId__c' => userId,
            'promptTemplateDevName__c' => promptDevName,
            'model__c' => model,
            'feature__c' => feature,
            'timestamp__c' => ts,
            'promptTokens__c' => pt,
            'completionTokens__c' => ct,
            'totalTokens__c' => pt + ct,
            'prompt__c' => 'Unit-test prompt for ' + promptDevName
        };
        return deserialize('GenAIGatewayRequest__dlm', body);
    }

    public static SObject makeResponse(String requestId, String responseId) {
        return deserialize(
            'GenAIGatewayResponse__dlm',
            new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => 'GenAIGatewayResponse__dlm' },
                'generationRequestId__c' => requestId,
                'generationResponseId__c' => responseId,
                'timestamp__c' => DateTime.now()
            }
        );
    }

    public static SObject makeGeneration(String responseId, String genId, String text) {
        return deserialize(
            'GenAIGeneration__dlm',
            new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => 'GenAIGeneration__dlm' },
                'generationResponseId__c' => responseId,
                'generationId__c' => genId,
                'responseText__c' => text,
                'timestamp__c' => DateTime.now()
            }
        );
    }

    public static SObject makeFeedback(String genId, String userId, String feedback, String action) {
        return deserialize(
            'GenAIFeedback__dlm',
            new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => 'GenAIFeedback__dlm' },
                'feedbackId__c' => 'fb_' + genId,
                'generationId__c' => genId,
                'userId__c' => userId,
                'feedback__c' => feedback,
                'action__c' => action,
                'timestamp__c' => DateTime.now()
            }
        );
    }

    public static SObject makeQuality(String qualityId, String genId, Boolean isToxic) {
        return deserialize(
            'GenAIContentQuality__dlm',
            new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => 'GenAIContentQuality__dlm' },
                'id__c' => qualityId,
                'parent__c' => genId,
                'isToxicityDetected__c' => isToxic ? 'true' : 'false',
                'timestamp__c' => DateTime.now()
            }
        );
    }

    public static SObject makeCategory(String qualityId, String category, String value) {
        return deserialize(
            'GenAIContentCategory__dlm',
            new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => 'GenAIContentCategory__dlm' },
                'parent__c' => qualityId,
                'category__c' => category,
                'value__c' => value,
                'timestamp__c' => DateTime.now()
            }
        );
    }

    /**
     * Generic builder for any DMO SObject — pass the type name and the
     * fields you want set. The `attributes.type` entry is added
     * automatically.
     */
    public static SObject makeDmo(String typeName, Map<String, Object> fields) {
        Map<String, Object> body = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => typeName }
        };
        if (fields != null) {
            body.putAll(fields);
        }
        return deserialize(typeName, body);
    }

    // ── AggregateResult helpers ────────────────────────────────────────────

    /**
     * Real-aggregate trick: produce a single AggregateResult by running
     * `SELECT COUNT(Id) <alias> FROM User WHERE Id = :seedId`. The
     * resulting row's `alias` value is always 1; callers needing
     * specific values (counts, sums) pair this with a wrapper they
     * control. For tests that only need *shape* (a non-null
     * AggregateResult), this is enough.
     */
    public static AggregateResult oneRowAggregate() {
        List<AggregateResult> r = [SELECT COUNT(Id) cnt FROM User WHERE Id = :UserInfo.getUserId()];
        return r[0];
    }

    /**
     * Multi-alias AggregateResult fixture using the real-aggregate trick.
     * Seeds an Account with the given numeric/string fields, runs
     * `SELECT … GROUP BY` against that single row, and returns the
     * resulting AggregateResult.
     *
     * Mapping:
     *   gkey  → Account.Name
     *   uid   → Account.AccountNumber  (User aggregate group key)
     *   pdn   → Account.TickerSymbol   (Prompt dev name group key — groupable)
     *   mdl   → Account.Site           (Model group key)
     *   cnt   → MAX(Account.NumberOfEmployees)
     *   pt    → MAX(Account.AnnualRevenue)
     *   ct    → MAX(Account.NumberOfEmployees) (re-aliased; only set one)
     *   tt    → SUM(Account.AnnualRevenue) over the seed row(s)
     *
     * Caller passes the desired aliases + values; the helper picks the
     * correct seed-field mapping. Tests rarely need more than 3-4
     * aliases per call.
     *
     * Returns a single-row AggregateResult.
     */
    public static AggregateResult aggregateRow(Map<String, Object> aliasValues) {
        Account a = seedAccountForAggregate(aliasValues);
        return querySingleAggregate(a.Id, aliasValues);
    }

    /**
     * Single-row totals aggregate with independent `cnt`, `pt`, `ct` values.
     *
     * Service paths that read `dao.getRequestTotals(...)` expect a single
     * AggregateResult carrying COUNT(Id), SUM(promptTokens), SUM(completionTokens),
     * SUM(totalTokens). Because MAX/MIN/SUM of a single Account row collapse to
     * the same value, the regular `aggregateRow` helper can't deliver pt and ct
     * independently. This helper seeds TWO Accounts in the same group so:
     *   - MAX(AnnualRevenue) = pt
     *   - MIN(AnnualRevenue) = ct
     *   - SUM(AnnualRevenue) = pt + ct (= tt)
     *   - MAX(NumberOfEmployees) = cnt
     */
    public static AggregateResult totalsAggregate(Integer cnt, Decimal pt, Decimal ct) {
        String groupName = 'fixture_totals_' + System.currentTimeMillis() + '_' + Crypto.getRandomLong();
        Account hi = new Account(Name = groupName, AnnualRevenue = pt, NumberOfEmployees = cnt);
        Account lo = new Account(Name = groupName, AnnualRevenue = ct, NumberOfEmployees = 0);
        insert new List<Account>{ hi, lo };
        List<AggregateResult> rs = [
            SELECT
                COUNT(Id) cntRows,
                MAX(NumberOfEmployees) cnt,
                MAX(AnnualRevenue) pt,
                MIN(AnnualRevenue) ct,
                SUM(AnnualRevenue) tt,
                MIN(CreatedDate) minTs,
                MAX(CreatedDate) maxTs
            FROM Account
            WHERE Name = :groupName
            GROUP BY Name
        ];
        return rs.isEmpty() ? null : rs[0];
    }

    /**
     * Multi-row variant — pass a list of alias maps, one per group. The
     * helper seeds N Accounts and groups by `gkey` (Account.Name).
     */
    public static List<AggregateResult> aggregateRows(List<Map<String, Object>> rows) {
        List<Account> accs = new List<Account>();
        for (Map<String, Object> r : rows) {
            accs.add(buildAccountForAggregate(r));
        }
        insert accs;
        Set<Id> ids = new Set<Id>();
        for (Account a : accs) {
            ids.add(a.Id);
        }
        // Build SELECT clause from the union of aliases requested. Always
        // project pt/ct/minTs/maxTs so service paths that read prompt/completion
        // tokens or first/last seen timestamps off the aggregate row don't crash
        // with "Invalid field".
        Set<String> aliasUnion = new Set<String>();
        for (Map<String, Object> r : rows) {
            aliasUnion.addAll(r.keySet());
        }
        aliasUnion.add('pt');
        aliasUnion.add('ct');
        aliasUnion.add('minTs');
        aliasUnion.add('maxTs');
        String soql = buildAggregateSelect(aliasUnion, true);
        soql += ' FROM Account WHERE Id IN :ids GROUP BY Name, AccountNumber, TickerSymbol, Site';
        return Database.query(soql);
    }

    private static Account seedAccountForAggregate(Map<String, Object> aliasValues) {
        Account a = buildAccountForAggregate(aliasValues);
        insert a;
        return a;
    }

    private static Account buildAccountForAggregate(Map<String, Object> aliasValues) {
        Account a = new Account(Name = 'fixture_' + System.currentTimeMillis());
        if (aliasValues.containsKey('gkey')) {
            a.Name = String.valueOf(aliasValues.get('gkey'));
        }
        if (aliasValues.containsKey('uid')) {
            a.AccountNumber = String.valueOf(aliasValues.get('uid'));
        }
        if (aliasValues.containsKey('pdn')) {
            a.TickerSymbol = String.valueOf(aliasValues.get('pdn'));
        }
        if (aliasValues.containsKey('mdl')) {
            a.Site = String.valueOf(aliasValues.get('mdl'));
        }
        if (aliasValues.containsKey('cnt')) {
            a.NumberOfEmployees = toInt(aliasValues.get('cnt'));
        }
        if (aliasValues.containsKey('tt')) {
            a.AnnualRevenue = toDec(aliasValues.get('tt'));
        }
        return a;
    }

    private static AggregateResult querySingleAggregate(Id seedId, Map<String, Object> aliasValues) {
        // Always project pt/ct/minTs/maxTs so service paths that read prompt/completion
        // tokens or first/last seen timestamps don't crash with "Invalid field".
        Set<String> aliases = new Set<String>(aliasValues.keySet());
        aliases.add('pt');
        aliases.add('ct');
        aliases.add('minTs');
        aliases.add('maxTs');
        String soql = buildAggregateSelect(aliases, false);
        soql += ' FROM Account WHERE Id = :seedId GROUP BY Name, AccountNumber, TickerSymbol, Site';
        List<AggregateResult> rs = Database.query(soql);
        return rs.isEmpty() ? null : rs[0];
    }

    private static String buildAggregateSelect(Set<String> aliases, Boolean includeAll) {
        List<String> parts = new List<String>();
        if (aliases.contains('gkey')) {
            parts.add('Name gkey');
        }
        if (aliases.contains('uid')) {
            parts.add('AccountNumber uid');
        }
        if (aliases.contains('pdn')) {
            parts.add('TickerSymbol pdn');
        }
        if (aliases.contains('mdl')) {
            parts.add('Site mdl');
        }
        if (aliases.contains('cnt')) {
            parts.add('MAX(NumberOfEmployees) cnt');
        }
        if (aliases.contains('tt')) {
            parts.add('SUM(AnnualRevenue) tt');
        }
        if (aliases.contains('pt')) {
            parts.add('MAX(AnnualRevenue) pt');
        }
        if (aliases.contains('ct')) {
            parts.add('MIN(AnnualRevenue) ct');
        }
        if (aliases.contains('minTs')) {
            parts.add('MIN(CreatedDate) minTs');
        }
        if (aliases.contains('maxTs')) {
            parts.add('MAX(CreatedDate) maxTs');
        }
        return 'SELECT ' + String.join(parts, ', ');
    }

    private static Integer toInt(Object v) {
        if (v == null) {
            return 0;
        }
        if (v instanceof Integer) {
            return (Integer) v;
        }
        if (v instanceof Decimal) {
            return ((Decimal) v).intValue();
        }
        return Integer.valueOf(String.valueOf(v));
    }

    private static Decimal toDec(Object v) {
        if (v == null) {
            return 0;
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
        return Decimal.valueOf(String.valueOf(v));
    }

    // ── Internals ──────────────────────────────────────────────────────────

    private static SObject deserialize(String typeName, Map<String, Object> body) {
        Type t = Type.forName(typeName);
        if (t != null) {
            return (SObject) System.JSON.deserialize(System.JSON.serialize(body), t);
        }
        // Fallback for the package-validation scratch org: Data Cloud DMOs
        // are not provisioned, so Type.forName returns null. We deserialize
        // into Fm_Test_Dmo_Row__c, which carries the camelCase field shape
        // (userId__c, gatewayRequestId__c, etc.) the service code reads via
        // `r.get('field__c')`. The `attributes.type` is rewritten so the
        // shadow record's SObjectType resolves cleanly.
        return deserializeIntoShadow(body);
    }

    private static SObject deserializeIntoShadow(Map<String, Object> body) {
        Type shadow = Type.forName('Fm_Test_Dmo_Row__c');
        if (shadow == null) {
            return null;
        }
        Map<String, Object> rewritten = new Map<String, Object>();
        if (body != null) {
            rewritten.putAll(body);
        }
        rewritten.put('attributes', new Map<String, String>{ 'type' => 'Fm_Test_Dmo_Row__c' });
        return (SObject) System.JSON.deserialize(System.JSON.serialize(rewritten), shadow);
    }
}
