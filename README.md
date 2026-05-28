# FluentMetric AI

A Salesforce-native dashboard that makes Einstein Generative AI Audit &
Feedback data **humanly readable** — resolves User IDs to names, prompt
developer names to labels, pre-joins the 9+ Data Cloud DMOs, and presents
curated dashboards for admins, prompt engineers, and AI product owners.

Adoption analytics measure activity against an **entitled-population
denominator** (users in configured Permission Sets / Permission Set Groups /
Profiles) rather than total org users. Cost rendering is **Wallet-first**:
when the Consumption Tagging app is installed and Wallet costs are enabled,
dashboards show actuals; otherwise a tier-rate estimator surfaces an
`ESTIMATED` confidence badge so users know the basis.

Two editions ship from this repo. Pick the one that fits your licenses.

| | Lightning Edition | Tableau Next Edition |
|---|---|---|
| Package directory | `force-app/` | `force-app-tableau/` |
| Tableau license required | **No** | **Yes** (Tableau Next on Salesforce — *not* Tableau Cloud) |
| Surface | 19 native LWCs, 5 tabs | Lightning App Page (KPI tile + launcher + agent chat) + Tableau Next workspace dashboards |
| Conversational AI | — | FluentMetric Tableau Analyst agent (3 invocable actions over Data Cloud) |
| Apex dependency | Self-contained | Depends on the Lightning edition's `AiInsightsService` |
| Best for | Anyone with Data Cloud + Audit & Feedback | Customers with Tableau Next provisioned who want drag-and-drop pivot freedom + conversational analytics |

Edition matrix and design rationale → [Documents/Architect/editions.md](Documents/Architect/editions.md).

---

## Pick your path

> **Latest release:** see [CHANGELOG.md](CHANGELOG.md) for current install
> URLs (one per edition).

### 🛠️ I'm an **admin** installing FluentMetric AI

**Start here →** [Documents/Admin/](Documents/Admin/)

UI-first install runbooks, prerequisites, configuration, troubleshooting,
and upgrade guides. **No CLI required** — install via 2GP package URL,
assign a permset, smoke-test the dashboards.

| For | Read |
|---|---|
| **First install** | [01-prerequisites](Documents/Admin/01-prerequisites.md) → [02-install-lightning](Documents/Admin/02-install-lightning.md) → [04-getting-started](Documents/Admin/04-getting-started.md) |
| **Adding the Tableau Next edition** | [03-install-tableau](Documents/Admin/03-install-tableau.md) |
| **Tuning cost rates / adoption denominator** | [05-configure](Documents/Admin/05-configure.md) |
| **Something's not rendering** | [06-troubleshooting](Documents/Admin/06-troubleshooting.md) |

### 💻 I'm a **developer** extending or building on the package

**Start here →** [Documents/Developer/](Documents/Developer/)

Local-dev setup, coding standards, Apex / LWC / DMO contracts, and the 2GP
release runbook.

| For | Read |
|---|---|
| **First-time clone-deploy-test loop** | [local-dev](Documents/Developer/local-dev.md) |
| **Authoring new code** | [coding-standards](Documents/Developer/coding-standards.md) → [apex-services](Documents/Developer/apex-services.md) / [components](Documents/Developer/components.md) |
| **Authoritative DMO schema** | [live-schema](Documents/Developer/live-schema.md) |
| **Cutting a release** | [release](Documents/Developer/release.md) |

### 🏛️ I'm an **architect** evaluating or designing

**Start here →** [Documents/Architect/](Documents/Architect/)

Design rationale, ADRs, edition selection guide, semantic-model authoring,
agent data path.

| For | Read |
|---|---|
| **System overview** | [architecture](Documents/Architect/architecture.md) |
| **Edition fit** | [editions](Documents/Architect/editions.md) |
| **Why we built it this way** | [decisions/](Documents/Architect/decisions/) |

---

## Quick install (TL;DR)

For a Salesforce admin with the install URL from CHANGELOG.md in hand:

1. Click the URL while logged into the target org.
2. Install for Admins Only.
3. **Setup → Permission Sets → FluentMetric AI User → Assign** to your dashboard users.
4. App Launcher → **FluentMetric AI**.

Detailed runbook: [Documents/Admin/02-install-lightning.md](Documents/Admin/02-install-lightning.md).

For developers wanting source-deploy iteration:

```bash
make deploy-lightning TARGET_ORG=<alias>      # Lightning edition
make install-tableau TARGET_ORG=<alias>       # Full Tableau Next install
make help                                     # All targets
```

## Repo layout

```
sfdx-project.json              # Two packageDirectories — both editions
CHANGELOG.md                   # Release log + install URLs
README.md                      # This file
CLAUDE.md                      # Project context for Claude Code

force-app/                     # Lightning edition (default 2GP package)
force-app-tableau/             # Tableau Next edition (depends on Lightning)

config/                        # Scratch org definition
scripts/                       # Install / verify shell scripts
Makefile                       # Run `make help` to list targets

Documents/
├── Admin/                     # Admin runbooks (install, configure, troubleshoot)
├── Developer/                 # Developer reference (Apex, LWC, schema, release)
├── Architect/                 # Design docs + ADRs
└── _archive/                  # Historical / superseded docs
```
