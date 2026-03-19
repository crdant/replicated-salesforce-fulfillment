---
status: complete
priority: p1
issue_id: "050"
tags:
  - code-review
  - documentation
  - correctness
dependencies: []
---

# Phantom Makefile targets documented in README

## Problem Statement

The README references `make verify-replicated` (line 173) and `make replicated-clean` (line 178) but neither target exists in the Makefile. Users following the documented setup workflow will hit `make: *** No rule to make target 'verify-replicated'. Stop.` errors. The PR body references these as "from #46" but they are not present on this branch.

This is a documentation-code contract violation that affects both human users and agents.

## Findings

**File:** `README.md` lines 172-180 — Steps 3 and 4 of "Replicated Platform Setup"

**Flagged by:** architecture-strategist (High), code-simplicity-reviewer (removal recommended), agent-native-reviewer (Critical — agent will report failure and may not recover)

**Evidence:**
- `grep -rn 'verify-replicated\|replicated-clean' Makefile` returns zero matches
- README steps 3 and 4 promise functionality that does not exist

## Proposed Solutions

### Option A: Remove phantom target references from README
- **Pros:** Simplest fix, eliminates broken contract immediately
- **Cons:** Users lose visibility into planned verification/teardown workflow
- **Effort:** Small (delete 9 lines)
- **Risk:** Low

### Option B: Add `verify-replicated` and `replicated-clean` targets to Makefile
- **Pros:** README becomes accurate, users get complete workflow
- **Cons:** Scope creep — adds implementation beyond original PR intent
- **Effort:** Medium (need to implement verification and teardown logic)
- **Risk:** Medium — rushed implementation could introduce bugs

### Option C: Add "coming soon" note to README
- **Pros:** Sets expectations without breaking contract
- **Cons:** Incomplete documentation is still incomplete
- **Effort:** Small
- **Risk:** Low

## Recommended Action

Option A — remove the phantom steps. Add them back when the targets are implemented. Documenting unimplemented features is a YAGNI violation.

## Technical Details

**Affected files:**
- `README.md` lines 172-180

## Acceptance Criteria

- [ ] `make verify-replicated` either works or is not documented in README
- [ ] `make replicated-clean` either works or is not documented in README
- [ ] All `make` targets referenced in README exist in the Makefile

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #70 code review | All 3 configured review agents flagged this independently |

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
- Related: `docs/solutions/workflow/pr-description-style-mismatch.md`
