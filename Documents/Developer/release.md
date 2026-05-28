# Release Engineering — 2GP Unlocked Packages

> **Audience:** Maintainers cutting a new version. Admins installing a release should follow [Admin/02-install-lightning.md](../Admin/02-install-lightning.md) and [Admin/03-install-tableau.md](../Admin/03-install-tableau.md) instead.

FluentMetric AI ships as **two Unlocked Packages (2GP)** — one per edition — built from the same monorepo and authored against DevHub `cvk-dev`. Each tagged release produces a one-click install URL per edition, captured in [CHANGELOG.md](../../CHANGELOG.md).

## Why 2GP

- **One-click install URL per edition** (`/packaging/installPackage.apexp?p0=<04t...>`) — no CLI required for admins.
- **Versioned upgrades** — `1.0.0` → `1.1.0` ships through the same install URL.
- **Reversible** — admins can uninstall via Setup → Installed Packages.
- **No new infrastructure** — DevHub `cvk-dev` already provisioned.

## One-time DevHub setup

Run once per package, against DevHub `cvk-dev`. Captures `0Ho...` package IDs.

```bash
# Lightning edition
sf package create \
  --name "FluentMetric AI" \
  --description "Einstein GenAI Audit & Feedback dashboards" \
  --package-type Unlocked \
  --path force-app \
  --no-namespace \
  --target-dev-hub cvk-dev

# Tableau Next edition
sf package create \
  --name "FluentMetric AI for Tableau" \
  --description "FluentMetric AI — Tableau Next edition" \
  --package-type Unlocked \
  --path force-app-tableau \
  --no-namespace \
  --target-dev-hub cvk-dev
```

After `sf package create` finishes, copy each `0Ho...` ID into [sfdx-project.json](../../sfdx-project.json) under `packageAliases`, and add a `dependencies` entry on the Tableau package pointing at the Lightning package so the Tableau install URL also pulls Lightning automatically.

```jsonc
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true,
      "package": "FluentMetric AI",
      "versionNumber": "1.0.0.NEXT"
    },
    {
      "path": "force-app-tableau",
      "package": "FluentMetric AI for Tableau",
      "versionNumber": "1.0.0.NEXT",
      "dependencies": [
        { "package": "FluentMetric AI@LATEST" }
      ]
    }
  ],
  "packageAliases": {
    "FluentMetric AI": "0Ho...",
    "FluentMetric AI for Tableau": "0Ho..."
  }
}
```

## Per-release flow

The `make release VERSION=X.Y.Z` target wraps the per-release sequence. Manually it looks like:

```bash
# 1. Cut Lightning edition version
sf package version create \
  --package "FluentMetric AI" \
  --installation-key-bypass \
  --wait 20 \
  --target-dev-hub cvk-dev
# → captures 04t... subscriber package version ID

# 2. Cut Tableau edition version (depends on Lightning via packageDependency)
sf package version create \
  --package "FluentMetric AI for Tableau" \
  --installation-key-bypass \
  --wait 20 \
  --target-dev-hub cvk-dev

# 3. Promote both to released (not beta)
sf package version promote --package "FluentMetric AI@X.Y.Z-1" --target-dev-hub cvk-dev
sf package version promote --package "FluentMetric AI for Tableau@X.Y.Z-1" --target-dev-hub cvk-dev

# 4. Append CHANGELOG entry with both 04t... install URLs
#    (handled by make release; otherwise edit CHANGELOG.md by hand)

# 5. Tag and push
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z

# 6. Create GitHub Release at:
#    https://github.com/<owner>/<repo>/releases/new?tag=vX.Y.Z
#    Copy CHANGELOG entry into the release body.
```

### Install-URL format

Once `04t...` IDs are captured, the install URLs follow:

```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04t<rest-of-id>
```

Use `https://test.salesforce.com/...` for sandboxes. CHANGELOG.md uses production URLs by default; admins replace `login` with `test` when targeting sandboxes.

## Pre-release validation

Before promoting, install the freshly created `04t...` into a fresh scratch org from `cvk-dev` and walk both admin install guides end-to-end. The `make` targets cover:

```bash
# Provision a clean scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias fm-validate \
  --duration-days 7 \
  --target-dev-hub cvk-dev

# Install via the URL captured in step 1 above
sf package install \
  --package "04t..." \
  --target-org fm-validate \
  --wait 20

# Smoke-test
make verify-tableau TARGET_ORG=fm-validate
```

If smoke tests fail against the scratch org, **do not promote** — fix forward and cut a new beta version.

## Optional: CI automation (deferred)

A `.github/workflows/release.yml` triggered on `v*` tag push can run `make release` against `cvk-dev` using a stored `SFDX_AUTH_URL` secret. Out of scope for v1 — manual `make release` until the runbook stabilizes.

## Source-deploy fallback

The Tableau Next edition keeps [scripts/install-tableau-next.sh](../../scripts/install-tableau-next.sh) as a power-user / development path. Admins should not need it once 2GP install URLs are published; reserve it for engineers iterating against `cvk-dev` and for orgs where 2GP install isn't yet supported.

## Project structure (Salesforce DX)

The repo is a single SFDX project with two `packageDirectories`:

```
sfdx-project.json
force-app/                       # Lightning edition (default)
force-app-tableau/               # Tableau Next edition
config/project-scratch-def.json
scripts/                         # install / verify scripts
Documents/                       # this doc tree
```

Both editions share `sourceApiVersion: 62.0`. Org runtime is 66.0 — backward-compatible.

## Version-history hygiene

[CHANGELOG.md](../../CHANGELOG.md) is the source of truth for what's in each release. Per the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format:

- `## [Unreleased]` always sits at the top — accumulate changes here as they merge to `main`.
- On release, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` and start a fresh `[Unreleased]` block.
- Each released entry **must** include both edition `04t...` install URLs and a one-line "Upgrade notes" call-out (e.g., "Permset `FluentMetric_AI_User` adds new field-level read on `Enable_Wallet_Costs__c`").
- Admin install guides reference CHANGELOG entries by version, never hard-code a single `04t...` ID.
