# AI Insights for Salesforce — Design Documentation

## What This Is

A **Salesforce-native Lightning app** (unmanaged package) that surfaces actionable insights from the Einstein Generative AI Audit & Feedback data model. It resolves raw IDs to human-readable names, pre-joins the complex DMO relationships, and presents dashboards that answer the questions admins and AI product owners actually ask — without writing SQL or building custom reports.

## The Problem

The Einstein Audit & Feedback data lives in Data Cloud as DMOs (Data Model Objects). To get any useful insight today, you must:

- Write Data Cloud SQL in Query Editor with multi-table joins
- Manually resolve User IDs, Prompt Template developer names, and feature tags
- Understand the DMO schema (9+ tables with `__dlm` suffixes and `__c` field suffixes)
- Build one-off reports that can't be shared or reused across orgs

This makes it nearly impossible for admins, prompt engineers, and AI product owners to answer basic questions like "Who is using AI the most?" or "Which prompts get the worst feedback?"

## The Solution

A packaged Lightning app with:

- **Pre-built dashboards** that answer the top 10 questions about AI usage
- **Automatic ID resolution** — User IDs become names, prompt dev names become labels
- **No SQL required** — Apex service layer handles all DMO queries and joins
- **Deployable to any org** with Data Cloud + Einstein Audit & Feedback enabled

## Documents in This Set

| Document | Purpose |
|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System architecture, component map, data flow |
| [DATA-MODEL.md](./DATA-MODEL.md) | DMO schema reference, query patterns, join logic |
| [APEX-SERVICES.md](./APEX-SERVICES.md) | Apex service layer design, method signatures, caching |
| [COMPONENTS.md](./COMPONENTS.md) | LWC component specifications and wireframes |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Packaging strategy, prerequisites, installation guide |
| [IMPLEMENTATION-PLAN.md](./IMPLEMENTATION-PLAN.md) | Phased build plan with acceptance criteria |
| [CLAUDE-CODE-SETUP.md](./CLAUDE-CODE-SETUP.md) | Claude Code + sf-skills configuration for this project |

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Packaging | Unmanaged package (v1) → Unlocked package (v2) | Simplest for POC distribution; upgrade path exists |
| UI Framework | Lightning Web Components (LWC) | Native to Salesforce, packageable, SLDS styling |
| Data Access | Apex querying Data Cloud DMOs via SOQL | Runs in-org, respects permissions, packageable |
| Fallback Data Access | Data Cloud Connect REST API via Apex HttpRequest | For queries that hit SOQL limitations on DMOs |
| ID Resolution | Apex joins to User object + GenAIGatewayRequestTags for prompt names | Single service layer handles all resolution |
| Caching | Platform Cache (org partition) for User name lookups and prompt template maps | Avoid repeated SOQL on static reference data |

## Target Users

- **Salesforce Admins** — "Show me who's using AI and how much"
- **Prompt Engineers** — "Which prompts perform well? What outputs are they generating?"
- **AI Product Owners** — "What's our adoption rate? Where should we invest next?"
- **Compliance/Trust Teams** — "Are any outputs getting flagged for safety?"

## Prerequisites for Target Orgs

- Salesforce org with Data Cloud enabled
- Einstein Generative AI Audit & Feedback turned on (Setup → Einstein Generative AI → Audit, Analytics, and Monitoring Setup)
- Users need Data Cloud permissions to query DMOs
- API version 62.0+ (Winter '25 or later)
