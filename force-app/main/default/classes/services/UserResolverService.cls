/**
 * Turns raw DMO identifiers into human-readable labels — the mission of this app.
 *
 * Responsibilities:
 *   - User IDs → User.Name + profile + department (from standard SOQL)
 *   - Prompt template developer names → humanized labels
 *   - Platform Cache (org partition `FluentMetric_AI`) to avoid repeated SOQL
 *   - Graceful degradation when the cache partition is unavailable
 *
 * Live-org quirks handled here:
 *   - The sentinel `"NOT_SET"` is treated as its own "System Call" bucket,
 *     never resolved against the User object
 *   - Prompt template names come back from the DMO wrapped in double quotes
 *     (e.g. `"Atlas__GroundednessValidationPrompt"`) — we strip them before
 *     attempting GenAiPromptTemplate lookup or humanization
 *   - If the User ID does not resolve (deactivated, cross-org, etc), we
 *     return "Unknown User (<id>)" rather than failing the dashboard
 */
public with sharing class UserResolverService {
    @TestVisible
    private static final String CACHE_PARTITION = 'local.FluentMetric_AI';
    @TestVisible
    private static final String USER_CACHE_PREFIX = 'user_';
    @TestVisible
    private static final String PROMPT_CACHE_PREFIX = 'prompt_';
    @TestVisible
    private static final Integer USER_CACHE_TTL_SECONDS = 3600;
    @TestVisible
    private static final Integer PROMPT_CACHE_TTL_SECONDS = 14400;
    @TestVisible
    private static final String SYSTEM_SENTINEL = 'NOT_SET';
    @TestVisible
    private static final String SYSTEM_LABEL = 'System Call';

    public class ResolvedUser {
        @AuraEnabled
        public String userId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String profileName;
        @AuraEnabled
        public String department;

        public ResolvedUser(String userId, String name) {
            this.userId = userId;
            this.name = name;
        }
    }

    public Map<String, String> resolveUserNames(Set<String> userIds) {
        Map<String, String> resolved = new Map<String, String>();
        if (userIds == null || userIds.isEmpty()) {
            return resolved;
        }

        Set<String> cacheMisses = new Set<String>();
        for (String uid : userIds) {
            if (String.isBlank(uid) || uid == SYSTEM_SENTINEL) {
                resolved.put(uid, SYSTEM_LABEL);
                continue;
            }
            String cached = getCachedValue(USER_CACHE_PREFIX + normalizeKey(uid));
            if (cached != null) {
                resolved.put(uid, cached);
            } else {
                cacheMisses.add(uid);
            }
        }

        if (!cacheMisses.isEmpty()) {
            Set<Id> idsToQuery = new Set<Id>();
            for (String miss : cacheMisses) {
                Id asId = tryParseId(miss);
                if (asId != null) {
                    idsToQuery.add(asId);
                }
            }
            if (!idsToQuery.isEmpty()) {
                for (User u : [
                    SELECT Id, Name
                    FROM User
                    WHERE Id IN :idsToQuery
                    WITH USER_MODE
                ]) {
                    resolved.put(String.valueOf(u.Id), u.Name);
                    putCachedValue(
                        USER_CACHE_PREFIX + normalizeKey(String.valueOf(u.Id)),
                        u.Name,
                        USER_CACHE_TTL_SECONDS
                    );
                }
            }
            for (String miss : cacheMisses) {
                if (!resolved.containsKey(miss)) {
                    String fallback = 'Unknown User (' + miss + ')';
                    resolved.put(miss, fallback);
                }
            }
        }

        return resolved;
    }

    public Map<String, ResolvedUser> resolveUsersDetailed(Set<String> userIds) {
        Map<String, ResolvedUser> resolved = new Map<String, ResolvedUser>();
        if (userIds == null || userIds.isEmpty()) {
            return resolved;
        }

        Set<Id> idsToQuery = new Set<Id>();
        for (String uid : userIds) {
            if (String.isBlank(uid) || uid == SYSTEM_SENTINEL) {
                resolved.put(uid, new ResolvedUser(uid, SYSTEM_LABEL));
                continue;
            }
            Id asId = tryParseId(uid);
            if (asId != null) {
                idsToQuery.add(asId);
            } else {
                resolved.put(uid, new ResolvedUser(uid, 'Unknown User (' + uid + ')'));
            }
        }

        if (!idsToQuery.isEmpty()) {
            for (User u : [
                SELECT Id, Name, Profile.Name, Department
                FROM User
                WHERE Id IN :idsToQuery
                WITH USER_MODE
            ]) {
                ResolvedUser ru = new ResolvedUser(String.valueOf(u.Id), u.Name);
                ru.profileName = u.Profile != null ? u.Profile.Name : null;
                ru.department = u.Department;
                resolved.put(ru.userId, ru);
            }
            for (String uid : userIds) {
                if (!resolved.containsKey(uid)) {
                    resolved.put(uid, new ResolvedUser(uid, 'Unknown User (' + uid + ')'));
                }
            }
        }

        return resolved;
    }

    public Map<String, String> resolvePromptTemplateLabels(Set<String> rawDevNames) {
        Map<String, String> resolved = new Map<String, String>();
        if (rawDevNames == null || rawDevNames.isEmpty()) {
            return resolved;
        }

        Map<String, String> rawToStripped = new Map<String, String>();
        for (String raw : rawDevNames) {
            rawToStripped.put(raw, stripQuotes(raw));
        }

        Set<String> strippedToQuery = new Set<String>();
        for (String raw : rawDevNames) {
            String stripped = rawToStripped.get(raw);
            if (String.isBlank(stripped)) {
                resolved.put(raw, 'Unknown Prompt');
                continue;
            }
            String cached = getCachedValue(PROMPT_CACHE_PREFIX + normalizeKey(stripped));
            if (cached != null) {
                resolved.put(raw, cached);
            } else {
                strippedToQuery.add(stripped);
            }
        }

        if (!strippedToQuery.isEmpty()) {
            Map<String, String> officialLabels = queryPromptTemplateLabels(strippedToQuery);
            for (String raw : rawDevNames) {
                if (resolved.containsKey(raw)) {
                    continue;
                }
                String stripped = rawToStripped.get(raw);
                String label;
                if (officialLabels.containsKey(stripped)) {
                    label = officialLabels.get(stripped);
                } else {
                    label = humanizeDevName(stripped);
                }
                resolved.put(raw, label);
                putCachedValue(PROMPT_CACHE_PREFIX + normalizeKey(stripped), label, PROMPT_CACHE_TTL_SECONDS);
            }
        }

        return resolved;
    }

    @TestVisible
    private Map<String, String> queryPromptTemplateLabels(Set<String> devNames) {
        Map<String, String> out = new Map<String, String>();
        try {
            String soql =
                'SELECT DeveloperName, MasterLabel ' +
                'FROM GenAiPromptTemplate ' +
                'WHERE DeveloperName IN :devNames';
            List<SObject> results = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'devNames' => devNames },
                AccessLevel.USER_MODE
            );
            for (SObject r : results) {
                out.put((String) r.get('DeveloperName'), (String) r.get('MasterLabel'));
            }
        } catch (Exception e) {
            // GenAiPromptTemplate may not be queryable — fall back to humanization
        }
        return out;
    }

    @TestVisible
    private String stripQuotes(String raw) {
        if (String.isBlank(raw)) {
            return raw;
        }
        String s = raw.trim();
        if (s.startsWith('"') && s.endsWith('"') && s.length() >= 2) {
            s = s.substring(1, s.length() - 1);
        }
        return s;
    }

    @TestVisible
    private String humanizeDevName(String devName) {
        if (String.isBlank(devName)) {
            return 'Unknown Prompt';
        }
        // Common pattern: `Namespace__PromptTemplateName` — keep it compact
        String cleaned = devName.replace('__', ' · ').replace('_', ' ');
        // Add a single space before interior capital letters for CamelCase names
        cleaned = cleaned.replaceAll('([a-z])([A-Z])', '$1 $2');
        return cleaned.trim();
    }

    @TestVisible
    private Id tryParseId(String raw) {
        try {
            return Id.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private String normalizeKey(String raw) {
        // Platform Cache keys: alphanumeric + underscore, max length enforced by platform.
        String normalized = raw.replaceAll('[^a-zA-Z0-9]', '_');
        return normalized.length() > 50 ? normalized.substring(0, 50) : normalized;
    }

    @TestVisible
    private String getCachedValue(String key) {
        try {
            Cache.OrgPartition partition = getPartition();
            if (partition == null) {
                return null;
            }
            Object cached = partition.get(key);
            return cached == null ? null : String.valueOf(cached);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private void putCachedValue(String key, String value, Integer ttl) {
        try {
            Cache.OrgPartition partition = getPartition();
            if (partition != null) {
                partition.put(key, value, ttl);
            }
        } catch (Exception e) {
            // Cache unavailable — no-op; resolution still works, just uncached
        }
    }

    @TestVisible
    private Cache.OrgPartition getPartition() {
        try {
            return Cache.Org.getPartition(CACHE_PARTITION);
        } catch (Exception e) {
            return null;
        }
    }
}
