# Local Development Setup

> **Goal:** Get a clone-deploy-test loop running in under 10 minutes.

## Prerequisites

- **Salesforce CLI (`sf`)** — `npm install -g @salesforce/cli` or via the
  installer at <https://developer.salesforce.com/tools/sfdxcli>.
- **Git** + a GitHub account with access to the repo.
- **Node.js 22.7.5+** if you plan to run the optional `@tableau/mcp-server`
  for workbook authoring.
- **DevHub access** — preferably `cvk-dev` (the project's reference DevHub).
  If you have a different DevHub, scratch-org creation will work as long as
  it's enabled for Data Cloud + Einstein GenAI features.

## 1. Clone

```bash
git clone <repo-url> "FluentMetric AI"
cd "FluentMetric AI"
```

## 2. Authenticate to your DevHub

```bash
sf org login web --alias cvk-dev --set-default-dev-hub
```

(Use whatever alias matches your DevHub.)

## 3. Provision a scratch org

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias fm-dev \
  --duration-days 7 \
  --target-dev-hub cvk-dev \
  --set-default
```

The scratch-org definition (`config/project-scratch-def.json`) requests
`DataCloud` and `EinsteinGenAI` features. **If scratch-org creation fails
with a feature-not-licensed error**, your DevHub doesn't have the needed
provisioning. Use a sandbox connected to a properly licensed org instead.

## 4. Deploy the Lightning edition

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org fm-dev \
  --test-level RunLocalTests
```

Or via Make:

```bash
make deploy-lightning TARGET_ORG=fm-dev
```

## 5. Assign the Permission Set

```bash
sf org assign permset --name FluentMetric_AI_User --target-org fm-dev
```

## 6. Run tests

```bash
sf apex run test \
  --code-coverage \
  --result-format human \
  --target-org fm-dev
```

Coverage target: **80%+** across both editions.

## 7. (Optional) Add the Tableau Next edition

If you also want the Tableau edition:

```bash
make install-tableau TARGET_ORG=fm-dev
```

This orchestrator runs the full 7-step Tableau install
(see [../Admin/03-install-tableau.md](../Admin/03-install-tableau.md)).
After install, **manually activate the agent** in
`${INSTANCE_URL}/lightning/setup/EinsteinCopilot/home`.

## 8. Open the org

```bash
sf org open --target-org fm-dev
```

App Launcher → **FluentMetric AI** (and **FluentMetric AI Tableau** if you
installed it).

## Iterating

After making changes:

```bash
# Re-deploy what you've modified
sf project deploy start --source-dir force-app --target-org fm-dev

# Re-run only the tests you changed
sf apex run test \
  --tests AiInsightsServiceTest \
  --target-org fm-dev
```

## Pulling org-side changes back into source

If you've made changes in the org via Setup that you want to capture:

```bash
sf project retrieve start \
  --source-dir force-app \
  --target-org fm-dev
```

Review the diff carefully — the retrieve command will overwrite local
unstaged changes.

## Working against `cvk-dev` directly

`cvk-dev` is the reference DevHub *and* a fully-stocked dev org with 1,198+
real GenAI requests. Some debugging benefits from running against it
directly rather than against an empty scratch org.

```bash
make deploy-lightning TARGET_ORG=cvk-dev
```

> **Don't push experimental Apex to cvk-dev** without coordinating — it's
> shared infra for releases. Use a scratch org for normal iteration.

## Where things live

- **Apex services / DAOs / DTOs:** `force-app/main/default/classes/`
- **LWCs:** `force-app/main/default/lwc/`
- **Apex tests:** `force-app/main/default/classes/tests/`
- **Tableau-edition:** mirror layout under `force-app-tableau/`
- **Make targets:** `Makefile` (run `make help`)
- **Install scripts:** `scripts/`

## Running the validators

For Claude Code-authored changes, the LWC/Apex skills include validators
(see [coding-standards.md](coding-standards.md)). Run them via the skill
infrastructure rather than by hand.

## Troubleshooting

- **"Validator timed out / broken pipe"** when authoring LWCs — these are
  validator infra issues, not code errors. Re-run; if persistent, deploy
  and rely on the actual deploy to surface real issues.
- **Deploy fails on `__dlm` references** — confirm Data Cloud is enabled in
  the target org (`sf org list metadata --metadata-type CustomObject` should
  list DMOs).
- **"InsufficientPriv"** when running tests — your scratch org user is
  missing Data Cloud permset. Assign `FluentMetric_AI_User` plus your DevHub's
  Data Cloud admin permset.
