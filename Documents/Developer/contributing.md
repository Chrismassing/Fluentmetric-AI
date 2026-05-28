# Contributing

> Workflow for landing a change on `main`.

## Branching

- **Trunk:** `main`. CI runs against every PR; merges fast-forward.
- **Branch naming:** `feat/<short-slug>`, `fix/<short-slug>`,
  `docs/<short-slug>`, `chore/<short-slug>`. Match the prefix to the change
  type — it's not load-bearing in tooling, just a hint for reviewers.
- **One change per PR.** A "fix typo + refactor service + add new tab" PR
  will be asked to split.

## PR checklist

Before opening a PR:

- [ ] Tests pass locally:
      `sf apex run test --target-org fm-dev --code-coverage`
- [ ] Coverage on changed classes is **≥ 80%**.
- [ ] LWC bundles include all four files (`.html` / `.js` / `.css` /
      `.js-meta.xml`) with `apiVersion=62.0` and `isExposed=true` if
      consumed in a FlexiPage.
- [ ] No hard-coded English strings — Custom Labels are added/updated.
- [ ] `with sharing` on every new Apex class.
- [ ] No `ORDER BY COUNT(Id)` in DMO queries (sort in Apex).
- [ ] If you touched `AiInsightsService` or any DTO: the Tableau-edition
      consumers (`GetUsage*Action.cls`, `FmTableauNextController.cls`) still
      compile.
- [ ] `Documents/` is updated if behavior, schema, or admin runbooks
      changed. Personal trees:
      - **Admin-visible change** (new permset, new Custom Setting field,
        new install step) → update [../Admin/](../Admin/).
      - **Apex contract change** → update [apex-services.md](apex-services.md).
      - **DMO usage change** → update [live-schema.md](live-schema.md).
      - **Design intent change** → consider an ADR under
        [../Architect/decisions/](../Architect/decisions/).
- [ ] **CHANGELOG.md** has an entry under `## [Unreleased]` with the right
      subsection (Added / Changed / Fixed / Removed / Security).

## PR description

Use a tight three-section format:

```
## Why
<1–3 sentences — what problem is this solving, who reported it>

## What
<bulleted list of concrete changes>

## Test plan
<bulleted list of what you ran / verified, and how someone reviewing can
re-check>
```

Reviewers can read this in 60 seconds. Save the deep technical context for
inline review comments.

## Code review

- Self-review the diff before requesting review. Catch your own
  unintentional changes (debug `System.debug` left in, accidental
  reformatting).
- **Don't merge your own PR** unless it's a docs-only change to your own
  recent work. At least one teammate should approve substantive Apex / LWC
  changes.
- For changes that affect both editions, **flag both edition codepaths** in
  the description so the reviewer doesn't miss them.

## Tests

### Apex

- DAO interface + mock — every new DAO method gets a mock entry plus a
  service-level test that asserts the mock was called with the expected
  args.
- Use `AiInsightsTestFactory` to construct DTOs / fake user IDs. Don't
  duplicate fixture-building logic.
- `Test.startTest()` / `Test.stopTest()` around governor-limit-sensitive
  paths.

### LWC

- Jest suites under `__tests__/` for any non-trivial getter or handler.
  The repo currently doesn't enforce LWC coverage targets, but new
  components should ship with at least a smoke test.
- Manual smoke-test in a scratch org for any visual change. **Don't claim
  visual changes are correct based only on a passing build.**

## Commit messages

- One-line summary in imperative mood (`Add cost confidence badge`).
- Body optional but encouraged for non-obvious changes.
- Reference the GitHub issue number with `Closes #NN` in the body when
  applicable.
- Squash-merge by default; the squashed message becomes the merge commit.

## What goes through code review and what doesn't

Goes through review:
- Apex changes (any size).
- LWC changes that touch behavior.
- Docs that describe contracts (`apex-services.md`, schema docs, ADRs).
- CHANGELOG entries for promoted releases.

Doesn't strictly need review:
- Typo fixes in docs.
- Updates to your own scratch-org notes / personal markdown.

When in doubt, ask for review — the cost is low.

## Releasing

Cutting a 2GP version is a separate process documented in
[release.md](release.md). Don't `make release` from a personal branch —
release happens from `main` after merge.
