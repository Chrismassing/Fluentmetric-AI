# COMPONENTS.md — Lightning Web Component Specifications

## Component Inventory

```
force-app/main/default/lwc/
├── aiInsightsApp/                    // Main app container
├── aiInsightsOverview/               // Summary cards dashboard
├── aiInsightsDateFilter/             // Shared date range picker
├── aiInsightsUserAdoption/           // User adoption table
├── aiInsightsPromptAnalytics/        // Prompt template usage table
├── aiInsightsPromptOutputViewer/     // Output inspection for a selected prompt
├── aiInsightsTokenConsumption/       // Token usage chart
├── aiInsightsSafety/                 // Content safety overview
├── aiInsightsPreflightCheck/         // Prerequisites validation on first load
└── aiInsightsEmptyState/             // Reusable empty/error state display
```

## Lightning App Page Layout

The app uses a **Lightning App Page (FlexiPage)** with a single-column layout. Components are stacked vertically in a logical reading order. A shared date filter at the top broadcasts the selected range to all child components via Lightning Message Service (LMS).

```
┌─────────────────────────────────────────────────┐
│  aiInsightsPreflightCheck                       │
│  (Only shows if prerequisites are not met)      │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsDateFilter                           │
│  [Last 7 days ▼]  [Custom: _____ to _____]      │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsOverview                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────┐ │
│  │ Total   │ │ Unique  │ │ Accept  │ │ Total │ │
│  │Requests │ │ Users   │ │  Rate   │ │Tokens │ │
│  │  1,247  │ │   38    │ │  72%    │ │ 2.1M  │ │
│  └─────────┘ └─────────┘ └─────────┘ └───────┘ │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsUserAdoption                         │
│  ┌───────────────────────────────────────────┐  │
│  │ Name      │ Requests │ Last Used │ Accept │  │
│  │───────────│──────────│──────────│────────│  │
│  │ Jane Doe  │    142   │ Today    │  81%   │  │
│  │ John S.   │     98   │ Yesterday│  65%   │  │
│  │ ...       │          │          │        │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsPromptAnalytics                      │
│  ┌───────────────────────────────────────────┐  │
│  │ Prompt       │ Uses │ Users │ Tokens/Avg │  │
│  │──────────────│──────│───────│────────────│  │
│  │ Sales Email  │  340 │   22  │   1,240    │  │
│  │ Case Summary │  298 │   31  │     890    │  │
│  │ ...          │      │       │            │  │
│  └───────────────────────────────────────────┘  │
│  [Click row to see outputs ▼]                   │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsPromptOutputViewer                   │
│  (Visible when a prompt is selected above)      │
│  ┌───────────────────────────────────────────┐  │
│  │ Prompt: "Sales Email Generator"           │  │
│  │                                           │  │
│  │ ┌─ Output #1 ──────────────────────────┐  │  │
│  │ │ User: Jane Doe  │  Apr 15, 2026      │  │  │
│  │ │ Input: "Generate a pitch for..."      │  │  │
│  │ │ Output: "Dear John, I'm excited..."  │  │  │
│  │ │ Feedback: 👍 Accepted                 │  │  │
│  │ └─────────────────────────────────────┘  │  │
│  │ ┌─ Output #2 ──────────────────────────┐  │  │
│  │ │ ...                                  │  │  │
│  │ └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsTokenConsumption                     │
│  [Group by: Prompt ▼ | User | Day | Week]       │
│  ┌───────────────────────────────────────────┐  │
│  │  ████████████████████  Sales Email 45%    │  │
│  │  ████████████         Case Summary 28%    │  │
│  │  ██████               Lead Qualify 15%    │  │
│  │  ████                 Other 12%           │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│  aiInsightsSafety                               │
│  ┌─────────┐ ┌──────────────────────────────┐  │
│  │ Flagged  │ │ Category Breakdown           │  │
│  │  0.3%   │ │ Toxicity: 0.2% │ Hate: 0.0% │  │
│  │ (4/1247)│ │ Bias: 0.1%     │ ...         │  │
│  └─────────┘ └──────────────────────────────┘  │
│  [Recent flagged outputs listed below]          │
└─────────────────────────────────────────────────┘
```

## Component Specifications

### aiInsightsApp (Main Container)

**Purpose:** Top-level wrapper that holds all child components and manages the Lightning Message Service channel.

**Behavior:**
- On load, calls `checkPrerequisites()` to verify org setup
- If prerequisites fail, shows `aiInsightsPreflightCheck` only
- If prerequisites pass, renders all dashboard components
- Publishes date range changes via LMS to all children

**LMS Channel:** `AiInsightsDateRange__c` with fields:
- `startDate` (DateTime)
- `endDate` (DateTime)

### aiInsightsDateFilter (Date Range Picker)

**Purpose:** Shared date range selector that broadcasts to all components.

**UI:**
- Dropdown with presets: Last 7 days, Last 30 days, Last 90 days, Custom
- When "Custom" is selected, show two `lightning-input` date pickers
- Default selection: Last 30 days

**Behavior:**
- On change, publishes new date range to LMS channel
- All other components subscribe to this channel and re-fetch data

### aiInsightsOverview (Summary Cards)

**Purpose:** High-level KPI cards showing overall AI usage metrics.

**Data source:** `AiInsightsController.getOverview(startDate, endDate)`

**Cards (use `lightning-card` or SLDS card markup):**

| Card | Value | Format | Color Logic |
|---|---|---|---|
| Total Requests | `totalRequests` | Number with comma separator | Neutral |
| Unique Users | `uniqueUsers` | Number | Neutral |
| Acceptance Rate | `acceptanceRate` | Percentage | Green if >70%, yellow if 50-70%, red if <50% |
| Total Tokens | `totalInputTokens + totalOutputTokens` | Abbreviated (e.g., 2.1M, 340K) | Neutral |
| Feedback Given | `feedbackCount` | Number | Neutral |
| Safety Flags | `toxicFlagCount` | Number | Red if > 0, green if 0 |

**States:**
- Loading: Show `lightning-spinner` inside each card
- Empty: Show "No AI usage data found" with link to setup docs
- Error: Show inline error message

### aiInsightsUserAdoption (User Table)

**Purpose:** Sortable table showing per-user AI usage. Answers "How is User A utilizing AI?"

**Data source:** `AiInsightsController.getUsageByUser(startDate, endDate)`

**Columns:**

| Column | Field | Sortable | Format |
|---|---|---|---|
| User | `userName` | Yes | Text (link to user record) |
| Profile | `profileName` | Yes | Text |
| Department | `department` | Yes | Text |
| Requests | `requestCount` | Yes (default DESC) | Number |
| First Used | `firstUsed` | Yes | Relative date |
| Last Used | `lastUsed` | Yes | Relative date |
| Acceptance Rate | `feedbackRatio` | Yes | Percentage with color |
| Top Prompts | `topPrompts` | No | Comma-separated, max 3 |
| Total Tokens | `totalTokens` | Yes | Abbreviated number |

**Behavior:**
- Uses `lightning-datatable` with client-side sorting
- Click user name to navigate to User record (via `NavigationMixin`)
- Pagination: show first 25, "Load More" button
- Search/filter bar at top to filter by name or department

### aiInsightsPromptAnalytics (Prompt Table)

**Purpose:** Per-prompt template usage metrics. Answers "How is Prompt B adopted?"

**Data source:** `AiInsightsController.getUsageByPrompt(startDate, endDate)`

**Columns:**

| Column | Field | Sortable | Format |
|---|---|---|---|
| Prompt Template | `promptLabel` | Yes | Text |
| Feature | `featureName` | Yes | Badge/pill |
| Invocations | `invocationCount` | Yes (default DESC) | Number |
| Unique Users | `uniqueUserCount` | Yes | Number |
| Acceptance Rate | `acceptanceRate` | Yes | Percentage with color |
| Avg Tokens | `avgInputTokens + avgOutputTokens` | Yes | Number |
| Total Tokens | `totalTokens` | Yes | Abbreviated |
| Safety Flags | `toxicFlagCount` | Yes | Number, red if > 0 |

**Behavior:**
- Click a row to select that prompt → triggers `aiInsightsPromptOutputViewer` to load
- Selected row gets highlighted styling
- Dispatches custom event `promptselected` with `promptDevName`

### aiInsightsPromptOutputViewer (Output Inspector)

**Purpose:** Shows actual prompt inputs and LLM outputs for a selected template. Answers "What outputs do we see from Prompt C?"

**Data source:** `AiInsightsController.getPromptOutputs(promptDevName, startDate, endDate, 20)`

**Layout:** Vertical list of expandable cards, each showing one request/output pair.

**Per-output card:**
- Header: User name, date, feedback badge (👍/👎/edited/no feedback)
- Collapsed: First 200 chars of input and output
- Expanded: Full input prompt and full generated text
- Footer: Token counts (input/output), safety flag if applicable

**Behavior:**
- Hidden by default; appears when a prompt is selected in `aiInsightsPromptAnalytics`
- Subscribes to `promptselected` event from the prompt table
- "Load More" button to fetch additional outputs (paginated, 20 at a time)
- Expandable sections use `lightning-accordion` or custom toggle

### aiInsightsTokenConsumption (Token Chart)

**Purpose:** Visual breakdown of token consumption. Answers "How many tokens is Prompt D consuming?"

**Data source:** `AiInsightsController.getTokenConsumption(startDate, endDate, groupBy)`

**UI:**
- Toggle: Group by Prompt / User / Day / Week
- Horizontal bar chart showing top consumers
- Each bar split into input tokens (lighter) and output tokens (darker)
- Table below chart with exact numbers

**Implementation:**
- Use a simple HTML/CSS bar chart (SLDS-styled `div` bars) — avoids charting library dependency
- Alternatively, if the org has Chart.js available, use it — but don't make it a hard dependency
- Percentage labels on each bar

**Behavior:**
- Changing the "Group by" selector re-fetches data with new `groupBy` parameter
- Top 10 consumers shown; "Others" bucket for the rest

### aiInsightsSafety (Content Safety)

**Purpose:** Overview of content safety flags and trust metrics.

**Data source:** `AiInsightsController.getSafetyOverview(startDate, endDate)`

**UI:**
- Summary card: Overall flagged rate (percentage + count)
- Category breakdown: 8 categories with average scores and flag counts
- Recent flagged outputs: list similar to `aiInsightsPromptOutputViewer` but filtered to flagged items only

**Behavior:**
- Categories displayed as a simple table or card grid
- Color coding: green (<0.3 avg score), yellow (0.3-0.7), red (>0.7)
- Clicking a flagged output expands to show full details

### aiInsightsPreflightCheck (Prerequisites)

**Purpose:** Validates org setup before showing dashboards.

**Data source:** `AiInsightsController.checkPrerequisites()`

**UI:**
- Checklist of prerequisites with ✅ / ❌ status
- For failed checks, show description and link to Setup page
- "Refresh" button to re-check after admin makes changes

**Checks:**
- Data Cloud enabled and accessible
- Einstein Generative AI Audit & Feedback enabled
- DMOs are queryable (try a simple COUNT query)
- Current user has required permissions

### aiInsightsEmptyState (Reusable)

**Purpose:** Consistent empty/error state display used by all components.

**Props:**
- `title` (String) — e.g., "No Data Yet"
- `message` (String) — e.g., "AI usage data will appear here once users start interacting with Einstein AI features."
- `iconName` (String) — SLDS icon name
- `showSetupLink` (Boolean) — whether to show link to setup instructions

## Lightning Message Service (LMS) Design

**Channel:** `AiInsightsDateRange__c`

```xml
<!-- force-app/main/default/messageChannels/AiInsightsDateRange.messageChannel-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<LightningMessageChannel xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>AI Insights Date Range</masterLabel>
    <isExposed>true</isExposed>
    <lightningMessageFields>
        <fieldName>startDate</fieldName>
        <description>Start of date range filter</description>
    </lightningMessageFields>
    <lightningMessageFields>
        <fieldName>endDate</fieldName>
        <description>End of date range filter</description>
    </lightningMessageFields>
</LightningMessageChannel>
```

**Flow:**
1. `aiInsightsDateFilter` publishes on user selection change
2. All dashboard components subscribe and re-invoke their `@wire` or imperative calls
3. Components show individual loading spinners during re-fetch

## SLDS Styling Approach

- Use SLDS base components wherever possible (`lightning-card`, `lightning-datatable`, `lightning-badge`, `lightning-spinner`)
- Custom CSS only for: bar chart rendering, color-coded percentages, card grid layout
- Follow SLDS spacing tokens (`slds-m-around_medium`, `slds-p-around_small`, etc.)
- No external CSS frameworks — SLDS only for maximum compatibility across orgs
- Dark mode: not in v1, but use SLDS tokens so it comes free when Salesforce adds it

## Accessibility

- All tables use proper ARIA labels and scope attributes
- Color coding always paired with text (never color-only indicators)
- Keyboard navigation supported via native `lightning-datatable`
- Loading states announced to screen readers via `role="status"`
