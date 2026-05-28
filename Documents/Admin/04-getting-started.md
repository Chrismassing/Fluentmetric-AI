# 04 — Getting Started (for end users)

> **Audience:** End users — admins, prompt engineers, AI product owners —
> who've been granted access to FluentMetric AI. **5-minute walkthrough.**

## Open the app

1. Click the **App Launcher** (9-dot grid in the top-left of any Salesforce page).
2. Search for **FluentMetric AI**. Click it. *(If you don't see it, ask your
   admin — they probably haven't assigned the permission set yet.)*
3. Pin the app: click the **pin icon** in the App Launcher row. Now it's
   one click from your home tab.

## The header — one date pill controls everything

At the top of every tab is a **date pill** showing the current window (e.g.,
*"Last 30 days · Apr 28 – May 28"*). Click it to choose:

- **Quick ranges:** Today / Last 7 days / Last 30 days / Last 90 days / This quarter
- **Custom range:** pick start and end dates

Whatever you pick instantly re-runs every dashboard on every tab. **You only
have to set the date once per session.**

## The five tabs

| Tab | What it answers |
|---|---|
| **Overview** | The 30-second view. KPIs (requests, users, acceptance, tokens), top contributors, daily volume trend. **Start here every time.** |
| **Adoption** | Who's actually using AI? Adoption rate, top users, the "AI heavy users" Pareto chip, entitlement-based denominator. Use when leadership asks *"are we getting value from our license spend?"* |
| **Explorer** | Free-form pivot tool. Pick **Group by** + **Metric** + filters; or click a **preset chip** (Top prompts, Tokens by user, Acceptance by prompt, etc.). Bar chart + collapsible detail table. Click any group to drill into the entity side-sheet. |
| **Safety** | Toxicity / hate / violence / etc. flags. 8 content-safety category scores from Einstein's classifier. Use to investigate flagged outputs. |
| **Cost** | Flex Credit consumption + USD estimate. Confidence badge tells you whether the number is **ACTUAL** (Wallet-based), **HIGH** confidence, or **ESTIMATED** (tier-rate fallback). |

## The Explorer tab — your power tool

Most "I just need to know X" questions land in Explorer. Three ways to use it:

1. **Click a preset chip** — preset chips are curated (Group by, Metric)
   combos like *"Top prompts"* or *"Tokens by day"*. One-click results.
2. **Pick your own pivot** — choose **Group by** (User, Prompt, Model, Day)
   and **Metric** (Requests, Tokens, Acceptance Rate, etc.). Add filters
   via the **+ Add filter** dropdown.
3. **Drill in** — click any group label in the chart or table. A side-sheet
   slides in showing the underlying request rows, with **Open in Explorer**
   to pivot the same data further.

The detail table is **collapsed by default** — the chart already conveys
ranking. Open the table when you need exact numbers or want to export.

## Export

Top-right of the Explorer tab: **Download icon** exports the current pivot
(group + metric + filters) as a CSV. The CSV matches what's on screen.

## When dashboards show no data

- **Empty state with "No data for this pivot"** — your filters returned
  nothing. Widen the date range, remove a filter, or pick a different
  Group by.
- **All KPIs are zero on Overview** — your org has no Einstein Audit data
  in the selected window. Either expand the date range or check with your
  admin that Audit & Feedback is on. See [06-troubleshooting.md](06-troubleshooting.md).

## Tableau Next edition users

If you're on the Tableau Next edition, **FluentMetric AI Tableau** appears
as a separate app in the App Launcher. It hosts:

- **GenAI Snapshot tile** — same headline KPIs as the Lightning Overview.
- **Open in Tableau Next** — opens the FluentMetric workspace with four
  full-fidelity Tableau dashboards.
- **FluentMetric Tableau Analyst** (Einstein Copilot agent) — ask natural
  language questions like *"who used the most tokens last week?"*

The Lightning and Tableau editions don't share UI but read the same
underlying data — pick whichever fits your audience.
