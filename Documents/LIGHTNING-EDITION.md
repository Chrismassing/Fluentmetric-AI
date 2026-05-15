# FluentMetric AI — Lightning Edition

The original FluentMetric AI: a Salesforce-native dashboard app reading the
Einstein Generative AI Audit & Feedback DMOs through a 4-layer Apex stack.
**No Tableau license required.**

## Prerequisites

- Salesforce org with Data Cloud + Einstein Audit & Feedback enabled.
- 1,000+ rows of audit history are recommended to make the dashboards
  meaningful (the dashboards work with less, just sparser).
- (Recommended) Platform Cache partition `FluentMetric_AI` provisioned, 5+ MB,
  for User/Prompt name resolution caching.

## Install

### Source deploy from this repo

```bash
sf project deploy start \
    --source-dir force-app \
    --target-org <your-org> \
    --test-level RunLocalTests
```

### Permission Set assignment

```bash
sf org assign permset --name FluentMetric_AI_User --target-org <your-org>
```

## What gets deployed

- **Apex (26 classes):** controllers, services, DAO + interface, DTOs, tests.
  See [APEX-SERVICES.md](./APEX-SERVICES.md).
- **LWC (19 components):** the full Lightning dashboard surface. See
  [COMPONENTS.md](./COMPONENTS.md).
- **Lightning App + Tab + FlexiPage:** `FluentMetric_AI`,
  `FluentMetric_AI_Dashboard`.
- **Permission Set:** `FluentMetric_AI_User`.
- **Custom Setting + Custom Metadata Type** for cost configuration and rate
  cards.
- **Message channels** for date and filter coordination across LWCs.

## Configuration after install

1. Open the **FluentMetric AI** Lightning App.
2. Pick a date range from the header filter.
3. (Optional) In Setup → Custom Settings → `FluentMetric_Cost_Settings__c`,
   adjust the per-org Flex Credit rate or fallback model.

## Architecture summary

```
LWC -> @AuraEnabled Controller -> Service -> DAO -> Data Cloud DMOs
```

Full architecture in [ARCHITECTURE.md](./ARCHITECTURE.md). Data model in
[LIVE-SCHEMA.md](./LIVE-SCHEMA.md).

## Upgrading to the Tableau edition

The two editions don't share metadata. To add the Tableau edition alongside
the Lightning edition, deploy `force-app-tableau/` per
[TABLEAU-EDITION.md](./TABLEAU-EDITION.md). Both apps will appear in the App
Launcher, governed by separate Permission Sets.
