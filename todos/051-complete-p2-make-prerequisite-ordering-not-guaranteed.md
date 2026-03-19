---
status: complete
priority: p2
issue_id: "051"
tags:
  - code-review
  - architecture
  - makefile
dependencies: []
---

# Make prerequisite ordering not guaranteed for setup-replicated

## Problem Statement

The README states that `make setup-replicated` "runs `channels`, `enterprise-portal`, `entitlements`, and `webhook-subscription` in dependency order." However, Make prerequisites are a dependency set, not an ordered sequence. GNU Make processes them left-to-right by convention in single-job mode, but `make -j` will run them in parallel, breaking the implicit ordering.

There is a real dependency: `enterprise-portal` and `entitlements` call `hack/resolve-app-metadata`, which queries for the channel. If `channels` hasn't run yet and the channel doesn't already exist, this lookup fails.

## Findings

**File:** `Makefile` line 3 — `setup-replicated: channels enterprise-portal entitlements webhook-subscription`

**Flagged by:** architecture-strategist (Medium)

**Evidence:**
- Make manual: "The order in which the prerequisites are listed doesn't matter; make will build them in whatever order it thinks best"
- `make -j4 setup-replicated` would run all 4 targets concurrently

## Proposed Solutions

### Option A: Use ordered recipe calls instead of prerequisites
```makefile
setup-replicated:
	$(MAKE) channels
	$(MAKE) enterprise-portal
	$(MAKE) entitlements
	$(MAKE) webhook-subscription
```
- **Pros:** Guarantees sequential execution regardless of `-j` flags
- **Cons:** Slightly more verbose
- **Effort:** Small
- **Risk:** Low

### Option B: Keep current syntax, update README wording
- **Pros:** No code change
- **Cons:** `-j` parallelism still breaks things
- **Effort:** Small
- **Risk:** Medium — someone will eventually try `-j`

## Recommended Action

Option A — explicit ordered recipe calls. Makes the ordering a contract rather than an accident.

## Technical Details

**Affected files:**
- `Makefile` line 3

## Acceptance Criteria

- [ ] `make -j4 setup-replicated` runs targets sequentially
- [ ] README accurately describes execution behavior

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #70 code review | Make prereqs are sets, not sequences |

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
