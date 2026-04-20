# Claude Redesign Spec

**Date:** 2026-04-18
**Status:** Proposed
**Scope:** Claude tab first, then reuse patterns across other providers

## Goal

Redesign the Claude experience for a macOS menubar app so it feels like a native utility instead of a compressed dashboard.

The redesign should optimize for:

- 1-second glanceability
- low visual noise
- clear quota risk assessment
- native Mac utility behavior
- separation between quick monitoring and deep analysis

## Problem

The current Claude surface mixes two jobs into one popover:

1. Quick status checking
2. Historical analysis

That creates a few UX problems:

- too many cards compete for attention
- model usage and charts push critical quota status further down
- the popover behaves like a mini analytics dashboard instead of a fast utility
- the visual system is repetitive, dense, and only loosely aligned with macOS utility patterns

## User

Primary user:

- a Mac power user who keeps AIMeter in the menubar all day
- checks quota status in a few seconds between coding sessions
- wants immediate answers to:
  - am I safe?
  - what resets next?
  - which quota is the constraint?
  - do I need to change behavior right now?

Secondary user:

- a heavier Claude user who occasionally wants deeper model and daily usage analysis

## Product Intent

Claude in AIMeter should feel like:

- a compact control center for quota health
- fast, calm, and precise
- more like Activity Monitor meets Control Center
- less like a SaaS dashboard in a popover

## Mac-Specific Design Principles

1. Menubar surfaces should prioritize scanability over exhaustiveness.
2. The popover should answer the primary question before showing secondary detail.
3. Dense analysis belongs in a dedicated window, not in the transient popover.
4. Visual hierarchy should come from spacing, grouping, and typography before color.
5. Accent colors should communicate status, not decorate every surface.

## Information Architecture

Split Claude into two surfaces:

### Surface A: Menubar Popover

Purpose:

- quick status
- immediate decisions
- light account switching
- quick actions

Contents:

- provider header
- primary quota hero
- compact quota list
- concise health insights
- last updated + actions

### Surface B: Claude Analytics Window

Purpose:

- model distribution
- daily history
- longer-range inspection
- future export and comparisons

Contents:

- model usage
- daily usage chart
- totals and period summary
- future advanced breakdowns

## Recommended Popover Structure

Target width:

- 360 to 400 px

Target behavior:

- opens quickly
- stable height
- no long scroll for the common case

### Layout

```text
┌──────────────────────────────────────┐
│ Claude                    Max 5x  ⋯  │
│ Team / account switcher             │
├──────────────────────────────────────┤
│ Session Health                       │
│ 62%                     Reset in 3h  │
│ ████████████████░░░░░░░              │
│ Ahead of pace by 40%                 │
│ Runs out in ~40m at current speed    │
├──────────────────────────────────────┤
│ Limits                               │
│ Weekly                 36%  Fri 7am  │
│ Sonnet                  4%  Fri 7am  │
│ Claude Design          43%  Sat 11am │
│ Extra Credits          62%  $15.67   │
├──────────────────────────────────────┤
│ Insight                                │
│ Opus 4.7 drove most usage today       │
│ 31.6k messages this period            │
├──────────────────────────────────────┤
│ Updated just now   Open Analytics  ↻  │
└──────────────────────────────────────┘
```

## Popover Sections

### 1. Header

Contents:

- `Claude` title
- plan badge if present
- account switcher underneath or inline when needed
- overflow button for secondary actions

Rules:

- remove decorative summary duplication from the top
- keep this area calm and compact
- avoid stacking multiple chips that fight the main content

### 2. Primary Hero: Session Health

This replaces the current pattern of equal-weight cards.

Purpose:

- make the most time-sensitive quota impossible to miss

Contents:

- section label: `Session Health`
- large percentage
- reset countdown
- single progress bar
- pace summary
- optional urgency line when risk is high

Behavior:

- always use the session quota as the hero on Claude
- if the user is rate-limited or blocked, this hero transforms into the system-status surface

Why:

- the 5-hour window is the quota Mac users are most likely to check repeatedly
- it has the strongest “what do I do now?” value

### 3. Limits List

This replaces the current stack of repeated full cards.

Each row includes:

- icon
- name
- one-line descriptor
- percent
- reset time or dollar amount
- thin progress indicator

Rows:

- Weekly
- Sonnet, when present
- Claude Design, when present
- Extra Credits, when enabled

Rules:

- use compact grouped rows inside one shared section
- only show rows that exist in the response
- keep typography smaller than the hero so hierarchy stays obvious

### 4. Insight Row

Purpose:

- keep one lightweight analytic insight in the popover without turning it into a chart surface

Examples:

- `Opus 4.7 drove most usage today`
- `Usage is 22% below your 14-day average`
- `No Claude Code activity yet today`

Rules:

- max 2 lines
- no chart here
- if insight data is unavailable, hide the section entirely

### 5. Footer Actions

Actions:

- `Open Analytics`
- `Refresh`
- `Settings`

Status:

- `Updated just now`

Rules:

- keep actions textual and Mac-like
- avoid oversized bottom bars or dashboard-style control clusters

## Claude Analytics Window

This is the new home for:

- model usage
- daily usage
- larger date ranges
- future comparisons

### Layout

```text
┌─────────────────────────────────────────────────────┐
│ Claude Analytics                         Today 7D 14D All │
├─────────────────────────────────────────────────────┤
│ Overview                                            │
│ Total tokens | Total messages | Avg/day | Top model │
├─────────────────────────────────────────────────────┤
│ Model Usage                                         │
│ Opus 4.7      5.0K in   1.5M out   78% share       │
│ Sonnet 4.6   34.0K in   199K out   18% share       │
│ Haiku 4.5     9.1K in   91.0K out   4% share       │
├─────────────────────────────────────────────────────┤
│ Daily Usage                                         │
│ [messages bars + tokens line chart in full width]   │
├─────────────────────────────────────────────────────┤
│ Notes / insights                                    │
└─────────────────────────────────────────────────────┘
```

### Window Principles

- resizable
- keyboard-friendly
- supports more data without visual compression
- uses standard toolbar or segmented control patterns

## Visual Direction

### Tone

- dark, but less glossy
- controlled contrast
- professional, calm, technical

### Surface Strategy

- use grouped sections over repeated floating cards
- reduce the number of rounded rectangles
- use one strong primary surface, then quieter grouped rows

### Typography

- keep SF Pro and SF Compact
- increase distinction between section labels, primary metric, and secondary metadata
- let the hero percentage be the only oversized numeric element

### Color

- reserve bright color for state and the primary metric
- use neutral surfaces for most structure
- make green, yellow, red mean something consistently
- use provider accent color sparingly

### Motion

- minimal
- subtle progress updates and section transitions only
- avoid decorative hover scaling on every row

## Behavior Spec

### Empty States

- if Claude Code model data is unavailable, keep the popover usable and simply hide insight content
- if no optional quotas exist, the limits list collapses to only available rows

### Error States

When there is an authentication or fetch problem:

- replace the hero section with the error state
- retain the footer actions
- do not bury errors between cards

### Refresh States

- show a small inline refreshing indicator in the footer or header
- avoid replacing sections with large skeleton blocks unless first load has no data at all

## Mapping To Current Code

Current files involved:

- [AIMeterApp.swift](/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/AIMeterApp.swift:304)
- [PopoverView.swift](/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/PopoverView.swift:320)
- [ClaudeTabView.swift](/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/ClaudeTabView.swift:70)
- [UsageCardView.swift](/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/UsageCardView.swift:15)
- [ModelUsageView.swift](/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/ModelUsageView.swift:3)
- [TrendChartView.swift](/Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/TrendChartView.swift:4)

Recommended UI refactor sequence:

1. Refactor `ClaudeTabView` into distinct sections:
   - `ClaudeHeroView`
   - `ClaudeLimitsListView`
   - `ClaudeInsightView`
   - `ClaudeFooterView`
2. Remove `ModelUsageView` and `TrendChartView` from the popover.
3. Create a dedicated `ClaudeAnalyticsWindowController` and root view.
4. Reuse existing stats service in the new analytics window.
5. Apply the same surface model to Copilot, Codex, and other providers later.

## Success Criteria

The redesign succeeds if:

- a user can understand Claude quota health within 1 second
- the popover height becomes more stable and compact
- the primary action is obvious without scrolling
- analytics become easier to read because they are moved into a proper window
- the UI feels recognizably native to macOS utility patterns

## Recommendation

Do this redesign in two stages.

### Stage 1

Redesign only the Claude popover using the new hero + limits + insight + footer structure.

### Stage 2

Move model and daily usage into a dedicated Claude analytics window.

This is the cleanest way to validate the new direction before reworking every provider.
