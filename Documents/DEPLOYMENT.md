# DEPLOYMENT.md — Packaging & Deployment Guide

## Package Strategy

### v1: Unmanaged Package

**Why unmanaged for v1:**
- Simplest to create — done entirely from Setup UI, no CLI required
- Recipients can edit components after install (useful for early adopters who want to customize)
- Install via URL — share a link, customer clicks it, done
- No Dev Hub required
- No namespace conflicts

**Tradeoffs accepted:**
- No upgrade path — v2 requires recipients to manually update or reinstall
- No IP protection — all Apex source is visible and editable
- No dependency tracking — recipient can break things by editing packaged components

**Upgrade path:** Once v1 is validated with 3-5 design partners, migrate to an Unlocked Package (2GP) for versioned upgrades. This requires Salesforce CLI and a Dev Hub but is a one-time setup.

### Future: Unlocked Package (2GP)

When you're ready to graduate:
```bash
# Create the package (one-time)
sf package create \
  --name "AI Insights" \
  --description "Einstein AI Usage Analytics" \
  --package-type Unlocked \
  --path force-app \
  --no-namespace \
  --target-dev-hub MyDevHub

# Create a version
sf package version create \
  --package "AI Insights" \
  --path force-app \
  --wait 10 \
  --target-dev-hub MyDevHub

# Install in target org
sf package install \
  --package "AI Insights@1.0.0-1" \
  --target-org TargetOrg \
  --wait 10
```

## What Goes in the Package

### Included Components

| Component Type | Items | Notes |
|---|---|---|
| **Apex Classes** | AiInsightsController, AiInsightsService, UserResolverService, AiInsightsDAO, all DTOs, all test classes | Core application logic |
| **LWC Components** | All 10 components listed in COMPONENTS.md | Dashboard UI |
| **Lightning App** | AI_Insights (custom app) | Navigation entry point |
| **Custom Tab** | AI_Insights_Tab | Tab for the app |
| **FlexiPage** | AI_Insights_Dashboard | Lightning App Page layout |
| **Lightning Message Channel** | AiInsightsDateRange | Cross-component communication |
| **Permission Set** | AI_Insights_User | Access to app, tab, Apex classes |
| **Platform Cache Partition** | AiInsights (org partition) | For name resolution caching |
| **Custom Labels** | Various UI labels | For potential future localization |

### NOT Included (Prerequisites — Must Already Exist in Target Org)

| Requirement | Why Not Packaged | Customer Action |
|---|---|---|
| Data Cloud enablement | Org-level feature, cannot be packaged | Enable via Setup |
| Einstein Audit & Feedback | Org-level setting | Enable via Setup → Einstein Generative AI |
| Data Cloud user permissions | Per-user permission assignments | Assign via Permission Set |
| User object | Standard object, always present | None |
| GenAiPromptTemplate | Standard object, may not be present in all orgs | None (app degrades gracefully) |

## Project Structure (Salesforce DX)

```
ai-insights/
├── sfdx-project.json
├── README.md
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/
│           │   ├── controllers/
│           │   │   ├── AiInsightsController.cls
│           │   │   └── AiInsightsController.cls-meta.xml
│           │   ├── services/
│           │   │   ├── AiInsightsService.cls
│           │   │   ├── AiInsightsService.cls-meta.xml
│           │   │   ├── UserResolverService.cls
│           │   │   └── UserResolverService.cls-meta.xml
│           │   ├── dao/
│           │   │   ├── AiInsightsDAO.cls
│           │   │   ├── AiInsightsDAO.cls-meta.xml
│           │   │   ├── IAiInsightsDAO.cls
│           │   │   └── IAiInsightsDAO.cls-meta.xml
│           │   ├── dto/
│           │   │   ├── UsageOverviewDTO.cls
│           │   │   ├── UserUsageDTO.cls
│           │   │   ├── PromptUsageDTO.cls
│           │   │   ├── PromptOutputDTO.cls
│           │   │   ├── TokenConsumptionDTO.cls
│           │   │   ├── ContentSafetyDTO.cls
│           │   │   └── DateRangeFilter.cls
│           │   └── tests/
│           │       ├── AiInsightsControllerTest.cls
│           │       ├── AiInsightsServiceTest.cls
│           │       ├── AiInsightsDAOTest.cls
│           │       ├── UserResolverServiceTest.cls
│           │       └── AiInsightsTestFactory.cls
│           ├── lwc/
│           │   ├── aiInsightsApp/
│           │   │   ├── aiInsightsApp.html
│           │   │   ├── aiInsightsApp.js
│           │   │   ├── aiInsightsApp.css
│           │   │   └── aiInsightsApp.js-meta.xml
│           │   ├── aiInsightsOverview/
│           │   ├── aiInsightsDateFilter/
│           │   ├── aiInsightsUserAdoption/
│           │   ├── aiInsightsPromptAnalytics/
│           │   ├── aiInsightsPromptOutputViewer/
│           │   ├── aiInsightsTokenConsumption/
│           │   ├── aiInsightsSafety/
│           │   ├── aiInsightsPreflightCheck/
│           │   └── aiInsightsEmptyState/
│           ├── applications/
│           │   └── AI_Insights.app-meta.xml
│           ├── tabs/
│           │   └── AI_Insights.tab-meta.xml
│           ├── flexipages/
│           │   └── AI_Insights_Dashboard.flexipage-meta.xml
│           ├── messageChannels/
│           │   └── AiInsightsDateRange.messageChannel-meta.xml
│           ├── permissionsets/
│           │   └── AI_Insights_User.permissionset-meta.xml
│           ├── cachePartitions/
│           │   └── AiInsights.cachePartition-meta.xml
│           └── labels/
│               └── CustomLabels.labels-meta.xml
├── config/
│   └── project-scratch-def.json
├── scripts/
│   └── setup/
│       └── create-scratch-org.sh
└── docs/
    └── (these design docs)
```

## sfdx-project.json

```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true
    }
  ],
  "name": "ai-insights",
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "62.0"
}
```

## Scratch Org Definition (for development)

```json
{
  "orgName": "AI Insights Dev",
  "edition": "Enterprise",
  "features": [
    "DataCloud",
    "EinsteinGenAI"
  ],
  "settings": {
    "lightningExperienceSettings": {
      "enableS1DesktopEnabled": true
    }
  }
}
```

**Note:** Scratch org features for Data Cloud and Einstein GenAI may require special permissions on your Dev Hub. If scratch org creation fails with these features, use a sandbox instead for development.

## Creating the Unmanaged Package (v1)

### Step-by-step in Setup UI:

1. **Setup → Package Manager → New**
   - Package Name: "AI Insights"
   - Description: "Einstein AI Usage Analytics — dashboards for Audit & Feedback data"
   - Language: English

2. **Add Components**
   - Click "Add" on the package
   - Add each Apex class, LWC, App, Tab, FlexiPage, Message Channel, Permission Set, Cache Partition, and Custom Labels
   - Salesforce will auto-detect most dependencies

3. **Upload**
   - Click "Upload" on the package
   - Version Name: "1.0"
   - Version Number: "1.0"
   - Set a password (optional) or leave open
   - Upload completes → generates an install URL

4. **Share the Install URL**
   - URL format: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04t...`
   - Customer clicks URL, logs into their org, approves installation
   - They then assign the "AI Insights User" permission set to relevant users

## Post-Installation Steps (for the customer)

Document these clearly — include in a "Getting Started" guide:

1. **Verify prerequisites:**
   - Data Cloud is enabled
   - Einstein Generative AI Audit & Feedback is turned on
   - At least some AI usage exists in the org (otherwise dashboards will be empty)

2. **Assign permissions:**
   - Assign "AI Insights User" permission set to users who need dashboard access
   - Ensure users also have Data Cloud permissions to query DMOs

3. **Access the app:**
   - Click the App Launcher (9-dot grid)
   - Search for "AI Insights"
   - Click to open

4. **First load:**
   - The preflight check will validate everything
   - If any checks fail, follow the on-screen guidance

## Deployment Commands (for development workflow)

```bash
# Deploy to sandbox for testing
sf project deploy start \
  --source-dir force-app \
  --target-org MySandbox

# Run all tests
sf apex run test \
  --code-coverage \
  --result-format human \
  --target-org MySandbox

# Retrieve after making changes in the org
sf project retrieve start \
  --source-dir force-app \
  --target-org MySandbox
```

## Version History Template

| Version | Date | Changes |
|---|---|---|
| 1.0 | TBD | Initial release — Overview, User Adoption, Prompt Analytics, Token Consumption, Safety dashboards |
| 1.1 | TBD | Prompt Builder integration, export to CSV, trend charts |
| 2.0 | TBD | Migrate to Unlocked Package, add Agentforce Session Tracing (OTel API), multi-language support |
