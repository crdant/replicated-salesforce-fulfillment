---
status: pending
priority: p2
issue_id: "011"
tags:
  - code-review
  - tooling
  - agent-accessibility
dependencies: []
---

# Fix broken make credentials target

## Problem Statement

The `make credentials` Makefile target calls `ReplicatedCredentialManager.setApiToken(...)`, but no `ReplicatedCredentialManager` Apex class exists in the codebase. This means the documented credential setup path (`make credentials`) is broken for both humans and automated agents.

## Findings

**File:** `Makefile:8` — references nonexistent class `ReplicatedCredentialManager`

README.md line 129 instructs users to "Create a `Replicated_Vendor_Portal_API_Credential__mdt` record with your API token" but the documented CLI path (`make credentials`) doesn't work.

## Proposed Solutions

### Option A: Replace with sf CLI metadata deployment
- Use `sf` CLI to deploy a CMT record directly
- No new Apex class needed
- **Effort**: Small
- **Risk**: Low

### Option B: Create ReplicatedCredentialManager Apex class
- Implement the missing class with `setApiToken()` method
- Requires deployment of additional Apex
- **Effort**: Medium
- **Risk**: Low

### Option C: Defer to Named Credentials migration (issue #28)
- The CMT is planned for replacement with Named Credentials
- Fix the Makefile after migration
- **Effort**: None now
- **Risk**: Documented setup path remains broken until migration

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `make credentials` either works or is removed/updated with working instructions

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review — pre-existing issue, not introduced by this PR | Adjacent to credential rename work |

## Resources

- Makefile: line 8
- Issue #28: Named Credentials migration
