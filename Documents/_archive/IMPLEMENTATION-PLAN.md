# IMPLEMENTATION-PLAN.md — Phased Build Plan

## Overview

Six phases, each producing a working increment. Each phase has clear acceptance criteria so you know when it's done. Estimated effort assumes Claude Code + sf-skills doing the heavy lifting — you're guiding, reviewing, and testing.

```
Phase 0: Project Setup          (30 min)
Phase 1: Data Access Layer      (2-4 hours)
Phase 2: First Dashboard        (2-3 hours)
Phase 3: Full Dashboard Suite   (4-6 hours)
Phase 4: Polish & Edge Cases    (2-3 hours)
Phase 5: Package & Test Install (1-2 hours)
────────────────────────────────────────────
Total estimated:                 12-18 hours
```

## Phase 0: Project Setup

**Goal:** SFDX project initialized, connected to a dev org with Data Cloud, sf-skills installed.

**Tasks:**
1. Create SFDX project: `sf project generate --name ai-insights`
2. Connect to dev org or sandbox with Data Cloud enabled
3. Verify DMO access: run a test query in Data Cloud Query Editor
   - `SELECT COUNT(Id) FROM GenAIGatewayRequest__dlm` — must return a number
4. Install sf-skills for Claude Code (see CLAUDE-CODE-SETUP.md)
5. Copy these design docs into the project's `docs/` folder

**Acceptance Criteria:**
- [ ] `sf org list` shows connected org
- [ ] Data Cloud Query Editor returns data from at least one DMO
- [ ] SFDX project structure matches DEPLOYMENT.md
- [ ] Claude Code has sf-skills loaded and responsive

**Risk:** If your dev org doesn't have Data Cloud or Audit & Feedback enabled, this blocks everything. Get org access sorted first.

## Phase 1: Data Access Layer (Apex)

**Goal:** DAO, Service, and Controller classes that can query DMOs and return data. Tested with real data in your dev org.

**Build Order:**

### 1a. DTOs (15 min)
Create all DTO classes from APEX-SERVICES.md. These are simple data classes with `@AuraEnabled` fields.

**Claude Code prompt:**
> Using sf-apex skill: Create all DTO classes defined in docs/APEX-SERVICES.md. Each should be a standalone Apex class with @AuraEnabled fields and appropriate constructors. Place in force-app/main/default/classes/dto/

### 1b. DAO Layer (1-2 hours)
Create `IAiInsightsDAO` interface and `AiInsightsDAO` implementation.

**Claude Code prompt:**
> Using sf-apex and sf-soql skills: Create the IAiInsightsDAO interface and AiInsightsDAO implementation from docs/APEX-SERVICES.md. These query Data Cloud DMOs using the __dlm suffix. Reference docs/DATA-MODEL.md for exact field names. Start with getRequestsByDateRange and getRequestTags — I want to test these against my org before building the rest.

**Manual test:** Deploy to dev org, run in Anonymous Apex:
```apex
AiInsightsDAO dao = new AiInsightsDAO();
List<SObject> results = dao.getRequestsByDateRange(
    DateTime.now().addDays(-30), DateTime.now()
);
System.debug('Requests found: ' + results.size());
```

**CRITICAL:** This is the riskiest step. DMO SOQL may behave differently than expected. If queries fail, document the error and adjust. Possible issues:
- Field names may differ from documentation (verify against your org's actual DMO schema)
- Aggregate functions may not be supported
- Dynamic SOQL may have different behavior on DMOs

If SOQL on DMOs fails entirely, pivot to Data Cloud Connect REST API (documented in DATA-MODEL.md as fallback).

### 1c. UserResolverService (30 min)
Create the name resolution service with Platform Cache.

**Claude Code prompt:**
> Using sf-apex skill: Create UserResolverService from docs/APEX-SERVICES.md with Platform Cache support. Include graceful degradation if cache partition doesn't exist.

### 1d. Service Layer (1-2 hours)
Create `AiInsightsService` with the first two methods: `getOverview` and `getUsageByUser`.

**Claude Code prompt:**
> Using sf-apex skill: Create AiInsightsService with getOverview() and getUsageByUser() methods. It should use AiInsightsDAO for data access and UserResolverService for name resolution. Reference docs/APEX-SERVICES.md for method signatures and docs/DATA-MODEL.md for join logic.

### 1e. Controller (30 min)
Create `AiInsightsController` with the first two `@AuraEnabled` methods.

### 1f. Tests (1 hour)
Create test classes with mocked DAO.

**Acceptance Criteria:**
- [ ] `AiInsightsDAO.getRequestsByDateRange()` returns data from live DMOs
- [ ] `UserResolverService.resolveUsers()` correctly maps User IDs to names
- [ ] `AiInsightsController.getOverview()` returns a populated DTO in Anonymous Apex
- [ ] `AiInsightsController.getUsageByUser()` returns users with resolved names
- [ ] All test classes pass with 75%+ code coverage
- [ ] Controller is callable via Anonymous Apex in dev org

## Phase 2: First Dashboard (LWC)

**Goal:** A working Lightning App with the Overview and User Adoption components visible and functional.

**Build Order:**

### 2a. Lightning Message Channel (10 min)
Create the `AiInsightsDateRange` message channel.

### 2b. Date Filter Component (30 min)
Build `aiInsightsDateFilter` with preset date ranges and LMS publishing.

**Claude Code prompt:**
> Using sf-lwc skill: Create the aiInsightsDateFilter LWC component from docs/COMPONENTS.md. It should have a dropdown with presets (Last 7 days, Last 30 days, Last 90 days, Custom) and publish date range changes via the AiInsightsDateRange Lightning Message Channel.

### 2c. Empty State Component (15 min)
Build `aiInsightsEmptyState` — reusable across all components.

### 2d. Overview Dashboard Component (45 min)
Build `aiInsightsOverview` with summary KPI cards.

**Claude Code prompt:**
> Using sf-lwc skill: Create aiInsightsOverview LWC from docs/COMPONENTS.md. It subscribes to the AiInsightsDateRange LMS channel, calls AiInsightsController.getOverview(), and renders 6 KPI cards using SLDS styling. Include loading spinners and empty state handling.

### 2e. User Adoption Table (1 hour)
Build `aiInsightsUserAdoption` with sortable datatable.

### 2f. App, Tab, FlexiPage (30 min)
Create the Lightning App, Tab, and App Page to host the components.

**Claude Code prompt:**
> Using sf-metadata skill: Create a custom Lightning App called "AI Insights", a custom tab, and a FlexiPage that arranges aiInsightsDateFilter at the top, aiInsightsOverview below it, and aiInsightsUserAdoption below that. Also create a Permission Set called AI_Insights_User that grants access to the app, tab, and all Apex classes.

### 2g. Deploy and Test (30 min)
Deploy to dev org, assign permission set, open the app.

**Acceptance Criteria:**
- [ ] "AI Insights" appears in App Launcher
- [ ] Date filter changes update all visible components
- [ ] Overview cards show real numbers from the org
- [ ] User Adoption table shows users with resolved names
- [ ] Sorting works on all sortable columns
- [ ] Loading spinners appear during data fetch
- [ ] Empty state shows when no data exists

## Phase 3: Full Dashboard Suite

**Goal:** All remaining components built and wired up.

### 3a. Prompt Analytics Table + Service Methods (1.5 hours)
Build `getUsageByPrompt()` in service/controller, then the LWC.

### 3b. Prompt Output Viewer (1.5 hours)
Build `getPromptOutputs()` in service/controller, then the LWC.
Wire the "click prompt row → show outputs" interaction between components.

### 3c. Token Consumption Chart (1 hour)
Build `getTokenConsumption()` in service/controller, then the LWC with bar chart.

### 3d. Safety Dashboard (1 hour)
Build `getSafetyOverview()` in service/controller, then the LWC.

### 3e. Update FlexiPage (15 min)
Add all new components to the App Page layout.

**Acceptance Criteria:**
- [ ] All 6 dashboard sections render with real data
- [ ] Clicking a prompt row shows outputs in the viewer
- [ ] Token chart renders with grouped bars
- [ ] Safety section shows category breakdown
- [ ] All components respond to date filter changes
- [ ] No JavaScript console errors

## Phase 4: Polish & Edge Cases

**Goal:** Handle real-world scenarios, improve UX, add preflight check.

**Tasks:**

### 4a. Preflight Check Component (30 min)
Build `aiInsightsPreflightCheck` and wire it to show on first load.

### 4b. Error Handling (30 min)
- DMO query permission errors → friendly message
- Data Cloud not enabled → redirect to setup
- Empty results → contextual empty states per component
- Network timeouts → retry logic in LWC

### 4c. Performance (30 min)
- Verify `cacheable=true` is set on all read methods
- Add Platform Cache for prompt template name resolution
- Ensure no N+1 query patterns in service layer
- Test with large date ranges (90 days)

### 4d. UX Polish (1 hour)
- Number formatting (commas, abbreviations, percentages)
- Relative dates ("2 hours ago", "Yesterday")
- Color coding consistency
- Responsive layout (test on different screen widths)
- SLDS spacing and alignment audit

### 4e. Test Coverage (1 hour)
- Ensure all test classes pass
- Target 80%+ code coverage across all Apex
- Add negative test cases (empty results, invalid inputs)

**Acceptance Criteria:**
- [ ] Preflight check runs on first load and shows clear status
- [ ] All error scenarios show user-friendly messages (no raw exceptions)
- [ ] Performance acceptable with 30-day and 90-day date ranges
- [ ] Numbers are properly formatted throughout
- [ ] All Apex tests pass with 80%+ coverage
- [ ] No SLDS styling issues visible

## Phase 5: Package & Test Install

**Goal:** Unmanaged package created and successfully installed in a separate org.

**Tasks:**

### 5a. Create Unmanaged Package (30 min)
Follow DEPLOYMENT.md steps to create package in Setup UI.

### 5b. Test Install (30 min)
Install in a different org (sandbox or partner org). Verify:
- All components install without errors
- Permission set is present and assignable
- App appears in App Launcher after permission assignment
- Preflight check runs and shows correct status
- If target org has AI data: dashboards populate correctly
- If target org has no AI data: empty states show correctly

### 5c. Create Getting Started Guide (30 min)
Write a 1-page install and setup guide for customers.

### 5d. Document Known Limitations (15 min)
- DMO fields that may differ between API versions
- Platform Cache requirements
- Data retention limitations
- Any SOQL-on-DMO quirks discovered during development

**Acceptance Criteria:**
- [ ] Package uploads successfully
- [ ] Install URL works in a separate org
- [ ] Getting Started guide covers all post-install steps
- [ ] Known limitations documented

## Post-v1 Roadmap

| Feature | Phase | Description |
|---|---|---|
| Export to CSV | v1.1 | Download table data as CSV |
| Trend Charts | v1.1 | Time-series charts for usage over time |
| Prompt Builder Integration | v1.2 | Correlate with Prompt Builder template versions |
| Scheduled Snapshots | v1.2 | Apex scheduled job to snapshot daily metrics for historical trending |
| Agentforce Session Tracing | v2.0 | OTel API integration for agent-level analytics |
| Unlocked Package Migration | v2.0 | Upgrade from unmanaged to unlocked for versioned deployments |
| Multi-Language | v2.0 | Custom labels for localized UI |
