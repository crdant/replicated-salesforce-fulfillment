---
status: complete
priority: p3
issue_id: "035"
tags:
  - code-review
  - quality
dependencies: []
---

# Remove explicit empty constructor from ReplicatedPlatform

## Problem Statement

`ReplicatedPlatform.cls` has an explicit empty constructor with a comment explaining the absence of credential handling. In Apex, an implicit no-arg constructor is provided by the compiler when none is defined. The comment explains an absence, which is a minor anti-pattern.

## Findings

- **Source**: code-simplicity-reviewer
- **File**: `create-license/main/default/classes/ReplicatedPlatform.cls`, lines 3-5
- The constructor body is empty — identical behavior to the implicit default
- `ReplicatedFulfillment` calls `new ReplicatedPlatform()` which works identically either way
- 4 lines of code that add no functionality

```apex
public ReplicatedPlatform() {
    // No credential needed — Named Credential handles auth
}
```

## Proposed Solutions

### Option A: Delete the constructor entirely
- Remove lines 2-5 of ReplicatedPlatform.cls
- Apex provides implicit no-arg constructor
- **Effort**: Small
- **Risk**: None

### Option B: Keep as documentation
- The comment serves as a breadcrumb for developers expecting credential injection
- **Effort**: None
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `ReplicatedPlatform` compiles and works without explicit constructor
- [ ] `ReplicatedFulfillment` still instantiates correctly

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #54 code review | Minor simplification |

## Resources

- PR #54: Named Credentials migration
- `create-license/main/default/classes/ReplicatedPlatform.cls`: lines 3-5
