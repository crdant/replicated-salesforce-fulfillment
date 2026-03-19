---
status: complete
priority: p3
issue_id: "076"
tags:
  - code-review
  - testing
  - apex
dependencies:
  - "070"
  - "071"
  - "072"
---

# Test coverage gaps for edge cases

## Problem Statement

The test class covers all 7 plan-specified scenarios but is missing tests for edge cases identified during code review. These tests would catch regressions if the findings in todos 070-072 are implemented.

## Missing Tests

1. **Null/blank customer_id** — event with missing `customer_id` should produce no records (depends on todo #072)
2. **Cross-customer email match** — Lead with a different `Replicated_Customer_Id__c` should NOT be matched by email fallback (depends on todo #071)
3. **`is_first_user` as String** — event with `is_first_user: "true"` (string, not boolean) should be gracefully skipped (depends on todo #070)
4. **Mixed batch** — some events convert Leads, others take direct-create path in same execution (validates both paths interact correctly)

## Proposed Solutions

### Option A: Add targeted test methods

Add 3-4 focused test methods, one per gap. These are small, fast tests.

- Effort: Small
- Risk: None

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandlerTest.cls`
- **Database changes**: None

## Acceptance Criteria

- [ ] Test for blank customer_id → no records created
- [ ] Test for cross-customer email match → Lead not converted
- [ ] Test for non-boolean is_first_user → gracefully skipped
- [ ] Test for mixed batch → both paths execute correctly

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — security sentinel + architecture strategist |

## Resources

- PR: #91
- File: `EpUserJoinedHandlerTest.cls`
