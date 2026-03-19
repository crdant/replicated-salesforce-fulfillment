---
status: complete
priority: p2
issue_id: "016"
tags:
  - code-review
  - tooling
  - consistency
  - agent-accessibility
dependencies: []
---

# Extract channels target logic to hack/ script

## Problem Statement

The `channels` Makefile target has 5 lines of inline shell logic (variable capture, jq parsing, conditional branching), while every other non-trivial target in the Makefile delegates to a `hack/` script. This breaks the established project convention and makes the Makefile inconsistent.

Additionally, the output format differs between the "exists" path (human-readable sentence) and the "create" path (CLI table format), making it unreliable for agent/automation consumption.

## Findings

**File:** `Makefile:13-18` — Complex inline shell logic

**Pattern violation:** All other targets with logic delegate to `hack/` scripts:
- `hack/set-webhook-secret` — webhook secret setup
- `hack/clean` — org cleanup
- `hack/import` — data import

**Agent-native gap:** An agent invoking `make channels` cannot reliably capture the channel ID because output format varies by code path. Past learnings (docs/solutions/integration-issues/salesforce-webhook-endpoint-testing-integration.md) document a similar Makefile consistency issue with `${ORG_ALIAS}` vs hardcoded values.

**Simplification opportunity:** The channel ID is captured and displayed but never used downstream. The core logic (check existence, create if missing) can be expressed more concisely.

## Proposed Solutions

### Option A: Extract to hack/create-channel script
- Create `hack/create-channel` with proper arg parsing, env var validation, and structured output
- Makefile target becomes a one-liner: `hack/create-channel --app "$${REPLICATED_APP}" --name "$${REPLICATED_CHANNEL}"`
- Script can output JSON or just the channel ID consistently
- **Effort**: Small
- **Risk**: Low
- **Pros**: Most consistent with project conventions, easy to test independently, clear error messages
- **Cons**: Adds a new file

### Option B: Simplify inline with jq -e pattern
- Replace if/else with `jq -e ... >/dev/null 2>&1 || replicated channel create ...`
- Reduces to 3 lines, removes unnecessary variable capture
- **Effort**: Small
- **Risk**: Low
- **Pros**: No new file, simpler logic
- **Cons**: Still breaks the hack/ delegation pattern

### Option C: Keep as-is
- The current implementation is correct and secure
- It works for the immediate use case
- **Effort**: None
- **Risk**: None
- **Pros**: No changes needed
- **Cons**: Pattern inconsistency persists

## Recommended Action

Option A preferred for convention consistency. Option B acceptable as a lighter alternative.

## Technical Details

**Affected files:**
- `Makefile` — Replace inline logic with script call
- `hack/create-channel` (new) — Idempotent channel creation script

## Acceptance Criteria

- [ ] `make channels` delegates to a `hack/` script (or inline logic is simplified)
- [ ] Output format is consistent regardless of whether channel exists or is created
- [ ] Channel ID is emitted in a machine-parsable way
- [ ] Script/target fails clearly when required env vars are missing

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #48 code review | Identified pattern violation vs hack/ convention |

## Resources

- PR #48: https://github.com/crdant/replicated-salesforce-fulfillment/pull/48
- Past learning: docs/solutions/integration-issues/salesforce-webhook-endpoint-testing-integration.md
