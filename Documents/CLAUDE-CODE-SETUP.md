# CLAUDE-CODE-SETUP.md — Claude Code + sf-skills Configuration

## Installation

### 1. Install sf-skills (full experience)

```bash
curl -sSL https://raw.githubusercontent.com/Jaganpro/sf-skills/main/tools/install.sh | bash
```

This installs 36 skills, 7 agents, hook scripts, and the LSP engine. Restart Claude Code after installation.

### 2. Verify installation

```bash
# Check status
python3 ~/.claude/sf-skills-install.py --status
```

You should see all skills loaded including the ones critical for this project.

## Skills You'll Use Most

| Skill | When | Why |
|---|---|---|
| **sf-apex** | Building all Apex classes | TAF patterns, 150-point validation, LSP auto-fix |
| **sf-lwc** | Building all LWC components | SLDS 2, Jest tests, template validation |
| **sf-soql** | Writing DMO queries in DAO layer | Natural language → SOQL, query plan analysis |
| **sf-metadata** | Creating App, Tab, FlexiPage, Permission Set, Message Channel | Metadata generation and org queries |
| **sf-deploy** | Deploying to sandbox/scratch org | CI/CD automation with sf CLI v2 |
| **sf-testing** | Writing Apex test classes | Coverage analysis, mock patterns, bulk testing |
| **sf-debug** | Troubleshooting DMO query issues | Debug log analysis, governor limit fixes |
| **sf-permissions** | Creating and verifying Permission Set | Permission analysis, "Who has X?" |
| **sf-ai-agentforce-observability** | Understanding STDM data model | Session tracing extraction (for v2) |
| **sf-data** | Creating test data factories | SOQL patterns, test data generation |

## Agent Team Mapping

For this project, you'll primarily use two agents from the sf-skills team:

| Agent | Role in This Project |
|---|---|
| **ps-technical-architect** | Apex classes (DAO, Service, Controller, DTOs), SOQL query design, Data Cloud integration patterns |
| **fde-experience-specialist** | LWC components, SLDS styling, Lightning App Page layout, LMS design |

The **fde-strategist** can orchestrate if you want to run multiple agents in parallel, but for a solo vibe coding session, just invoke the relevant agent directly.

## Project-Level Configuration

### CLAUDE.md (place in project root)

Create a `CLAUDE.md` file in your project root. Claude Code reads this automatically on every session.

```markdown
# AI Insights — Project Context for Claude Code

## What This Project Is
A Salesforce-native Lightning app that visualizes Einstein Generative AI
Audit & Feedback data from Data Cloud DMOs. It resolves IDs to names and
presents pre-built dashboards. Packaged as an unmanaged package for
deployment to multiple orgs.

## Architecture
See docs/ARCHITECTURE.md for full details. Key points:
- 4-layer architecture: LWC → Controller → Service → DAO
- DAO queries Data Cloud DMOs using __dlm suffix
- UserResolverService resolves User IDs and prompt template names
- Platform Cache for name resolution performance
- Lightning Message Service for cross-component date filter

## Key Design Docs (READ BEFORE CODING)
- docs/DATA-MODEL.md — DMO schema, field names, query patterns
- docs/APEX-SERVICES.md — Apex class structure, method signatures, DTOs
- docs/COMPONENTS.md — LWC specifications, layout, behavior
- docs/DEPLOYMENT.md — Project structure, what goes in the package

## Coding Standards
- Apex: Use `with sharing` on all classes. Use `Database.query()` for DMO
  queries (dynamic SOQL needed for __dlm objects). All controller methods
  must be `@AuraEnabled(cacheable=true)` for reads.
- LWC: Use SLDS exclusively (no external CSS frameworks). Use Lightning
  Message Service for cross-component communication. All components must
  handle loading, empty, and error states.
- SOQL on DMOs: Field names end in __c, object names end in __dlm. Use
  LIKE instead of = for text comparisons. Always filter by date range.
- Testing: Use DAO interface + mock pattern. DMO data won't exist in test
  context. Target 80%+ coverage.

## File Organization
force-app/main/default/classes/controllers/  — @AuraEnabled controllers
force-app/main/default/classes/services/     — Business logic
force-app/main/default/classes/dao/          — DMO SOQL queries
force-app/main/default/classes/dto/          — Data transfer objects
force-app/main/default/classes/tests/        — Test classes
force-app/main/default/lwc/                  — Lightning Web Components

## Current Phase
[UPDATE THIS AS YOU PROGRESS]
Currently in Phase 1: Data Access Layer. Building DAO and testing
DMO SOQL queries against dev org.

## Connected Org
[UPDATE WITH YOUR ORG ALIAS]
Dev org alias: MyDevOrg
API version: 62.0
```

### .claude/settings.json (optional overrides)

If you want to customize Claude Code behavior for this project:

```json
{
  "permissions": {
    "allow": [
      "sf project deploy start",
      "sf apex run test",
      "sf apex run",
      "sf org open",
      "sf data query"
    ]
  }
}
```

## Recommended Claude Code Workflow

### Starting a Session

```
claude

> I'm working on the AI Insights project. Read CLAUDE.md and docs/IMPLEMENTATION-PLAN.md.
> I'm currently on Phase [X]. Let's work on [specific task].
```

### Example Prompts by Phase

**Phase 1 — DAO Layer:**
```
Using sf-apex and sf-soql skills: Create the AiInsightsDAO class.
Read docs/DATA-MODEL.md for exact DMO field names and docs/APEX-SERVICES.md
for the method signatures. Start with getRequestsByDateRange().
Deploy to my org and test with Anonymous Apex.
```

**Phase 2 — First LWC:**
```
Using sf-lwc skill: Create the aiInsightsOverview LWC component.
Read docs/COMPONENTS.md for the exact specification. It should call
AiInsightsController.getOverview() and display 6 KPI cards using SLDS.
Subscribe to the AiInsightsDateRange Lightning Message Channel.
```

**Phase 3 — Prompt Analytics:**
```
Using sf-apex skill: Add getUsageByPrompt() to AiInsightsService and
AiInsightsController. Then using sf-lwc skill: create the
aiInsightsPromptAnalytics component. When a row is clicked, it should
dispatch a 'promptselected' event that aiInsightsPromptOutputViewer listens to.
```

**Phase 5 — Deployment:**
```
Using sf-deploy skill: Deploy all components to my sandbox.
Run all tests and verify 80%+ coverage. Then help me create
the unmanaged package following docs/DEPLOYMENT.md.
```

### Debugging DMO Query Issues

If a DMO SOQL query fails:

```
Using sf-debug skill: I'm getting this error when querying
GenAIGatewayRequest__dlm: [paste error]. The query is: [paste query].
Help me diagnose whether this is a field name issue, a permissions issue,
or a DMO SOQL limitation. If it's a limitation, help me pivot to the
Data Cloud Connect REST API fallback described in docs/DATA-MODEL.md.
```

## Hooks That Will Help You

The sf-skills hooks run automatically:

| Hook | What It Does for This Project |
|---|---|
| **PostToolUse (Apex)** | Validates Apex classes on save — catches sharing issues, SOQL patterns, null safety |
| **PostToolUse (LWC)** | Validates LWC JS and HTML — catches SLDS issues, template errors |
| **PreToolUse** | Guards against unbounded SOQL (important since DMO queries can be large) |
| **SessionStart** | Checks org connection, warms LSP servers |

## Common Pitfalls to Avoid

1. **Don't hardcode DMO field names without testing them first.** The documentation may not match your org's actual DMO schema. Always verify with a Query Editor query first.

2. **Don't try relationship queries on DMOs.** Use separate queries and join in Apex. DMOs don't support parent-child subqueries the way standard objects do.

3. **Don't skip the mock pattern for tests.** DMO data won't be available in Apex test context. Every DAO method needs a mockable interface.

4. **Don't use `=` for text comparisons on DMOs.** Use `LIKE` as per Salesforce documentation.

5. **Don't deploy without running tests.** Unmanaged package upload will fail if tests don't pass.

6. **Don't forget the Platform Cache partition.** It's a separate metadata component that needs to be created and included in the package.
