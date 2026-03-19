---
status: complete
priority: p2
issue_id: "014"
tags:
  - code-review
  - quality
  - shell
dependencies: []
---

# Simplify three-pass jq to single-pass pipeline

## Problem Statement

The new script makes three separate `jq` invocations chained through shell variables (lines 20-21, 28-29, 36-40) where the existing `hack/import` one-liner does it in a single `jq` expression. The three-pass approach is 40 lines; a single-pass version with env var validation is ~12 lines. The added complexity is justified as "better error messages" but this is a developer utility in `hack/`, not a user-facing CLI.

## Findings

**Code Simplicity Reviewer:** Three-pass jq with intermediate shell variables adds complexity over the proven single-pass approach. Granular error messages over-engineered for a `hack/` script — `set -u` and `:?` parameter expansion cover the env var checks in 2 lines instead of 10.

**Security Sentinel:** The three-pass approach does produce better intermediate error messages. The security benefit is marginal — validation is defensive hardening, not vulnerability prevention.

**Architecture Strategist:** The incremental validation (check app exists, then check channel exists) is "strictly better" than the inline version. This is a tradeoff between simplicity and error quality.

## Proposed Solutions

### Option A: Collapse to single-pass (Recommended)
- Use `:?` for env var checks (2 lines instead of 10)
- Single jq pipeline matching the existing pattern
- ~12 lines total instead of 40
- **Effort**: Small
- **Risk**: Low — error messages become less specific but still actionable

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${REPLICATED_APP:?REPLICATED_APP is not set}"
: "${REPLICATED_CHANNEL:?REPLICATED_CHANNEL is not set}"

replicated app ls --output json | jq --arg app "$REPLICATED_APP" --arg channel "$REPLICATED_CHANNEL" \
  '.[] | select(.app.slug == $app) | {
    app_name: .app.name,
    app_id: .app.id,
    channel_id: (.channels[] | select(.channelSlug == $channel) | .id)
  }'
```

### Option B: Keep current structure
- Granular error messages are helpful during debugging
- More lines but explicit about each failure point
- **Effort**: None
- **Risk**: None — code works correctly

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Script produces identical JSON output for valid inputs
- [ ] Script fails with actionable error for each failure mode (missing env var, bad app, bad channel)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #49 code review | Tradeoff between verbose error messages and script brevity for developer tools |

## Resources

- PR: #49
- File: `hack/resolve-app-metadata`
- File: `hack/import` (line 48 — existing single-pass pattern)
