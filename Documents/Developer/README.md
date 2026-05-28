# Developer Guide — FluentMetric AI

> **Audience:** Engineers extending the package, reading the DAO contract,
> or cutting a new release. Need to install the published package?
> [../Admin/README.md](../Admin/README.md). Need design rationale?
> [../Architect/README.md](../Architect/README.md).

## Reading order

1. **[local-dev.md](local-dev.md)** — Clone, scratch org, deploy, run tests.
2. **[apex-services.md](apex-services.md)** — Layered Apex contract:
   Controller → Service → DAO. DTOs and method signatures.
3. **[components.md](components.md)** — LWC inventory, layout, behavior.
4. **[live-schema.md](live-schema.md)** — **Authoritative** verified DMO
   schema from `cvk-dev`. Read this before authoring SOQL.
5. **[wallet-live-schema.md](wallet-live-schema.md)** — Digital Wallet DLO
   schema. Distinct conventions from the GenAI DMOs.
6. **[coding-standards.md](coding-standards.md)** — Apex / LWC / testing
   norms. Required reading before opening a PR.
7. **[contributing.md](contributing.md)** — Branch + PR + review workflow.
8. **[release.md](release.md)** — 2GP package version cut, CHANGELOG, GitHub
   Releases.

## Repo layout (one-liner)

```
sfdx-project.json                # Two packageDirectories — both editions
force-app/                       # Lightning edition (default package)
force-app-tableau/               # Tableau Next edition (depends on Lightning)
config/project-scratch-def.json  # Scratch org definition with Data Cloud + Einstein GenAI features
scripts/                         # install / verify shell scripts
Documents/                       # this doc tree
Makefile                         # `make help` for all targets
CHANGELOG.md                     # Release log + install URLs
```

Detailed structure for each `force-app*` directory: see
[apex-services.md](apex-services.md) and [components.md](components.md).

## How the two editions relate

The Tableau Next edition's Apex *delegates* to `AiInsightsService` from the
Lightning edition. **Lightning must be installed first** (or both deployed
together). The 2GP `sfdx-project.json` declares Tableau→Lightning as a
`packageDependency`, so installing the Tableau edition's URL pulls Lightning
along automatically.

When changing a public method on `AiInsightsService` or any DTO, **also
update the Tableau-edition consumers**:

- `force-app-tableau/main/default/classes/agent/GetUsageOverviewAction.cls`
- `force-app-tableau/main/default/classes/agent/GetUsageByUserAction.cls`
- `force-app-tableau/main/default/classes/agent/GetUsageByPromptAction.cls`
- `force-app-tableau/main/default/classes/FmTableauNextController.cls`

CI runs both editions' tests on every PR.

## Quick-reference targets

```bash
make help                                    # Lists every target
make deploy-lightning TARGET_ORG=<alias>     # Deploy Lightning edition
make install-tableau TARGET_ORG=<alias>      # Full Tableau Next install (orchestrator)
make verify-tableau TARGET_ORG=<alias>       # Smoke test the Tableau install
make release VERSION=X.Y.Z                   # Cut a 2GP version (see release.md)
```
