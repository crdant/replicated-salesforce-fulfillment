---
status: complete
priority: p2
issue_id: "001"
tags:
  - code-review
  - security
  - field-level-security
  - profiles
dependencies: []
---

# Admin editable=true is redundant with ModifyAllData and inconsistent with read-only intent

## Problem Statement

The Admin profile sets `editable=true` for all 10 `Replicated_Instance__c` fields, but:
1. CLAUDE.md documents `Replicated_Instance__c` as "read-only in SF"
2. The Admin profile already has `ModifyAllData` (line 625), which **overrides FLS entirely** — making `editable=true` functionally meaningless
3. The object's `sharingModel=Read` reinforces the read-only intent
4. If an admin manually edits `Instance_Id__c` (the reconciliation key), it could corrupt the Replicated sync

This finding was identified by 3 of 4 applicable review agents (security-sentinel, code-simplicity-reviewer, architecture-strategist).

## Findings

- **Security Sentinel**: Admin `editable=true` on `Instance_Id__c` (reconciliation key) is a medium-severity risk. Manual edits could break sync.
- **Simplicity Reviewer**: The editable=true creates a semantic distinction between Admin and non-Admin that has no practical effect and is harder to reason about. Making all 6 profiles identical simplifies the metadata.
- **Architecture Strategist**: Admin `editable=true` is functionally meaningless given `ModifyAllData`. Setting `editable=false` would be more truthful to the "read-only in SF" intent, even if the override makes it moot.

## Proposed Solutions

### Option A: Set all Admin FLS to editable=false (Recommended)
- Change all 10 `<editable>true</editable>` to `<editable>false</editable>` in Admin.profile-meta.xml
- Makes all 6 profiles identical for `Replicated_Instance__c`
- Documents-as-code the read-only intent
- **Pros**: Simplest, most consistent, matches documented intent
- **Cons**: Cosmetic change only (ModifyAllData already overrides)
- **Effort**: Small (10 line changes in 1 file)
- **Risk**: None — Admin retains full access through ModifyAllData

### Option B: Set only Instance_Id__c to editable=false on Admin
- Protect the reconciliation key specifically
- Keep other fields editable for troubleshooting
- **Pros**: Targeted protection of most critical field
- **Cons**: Same as Option A — ModifyAllData overrides anyway, and creates inconsistency within the Admin profile
- **Effort**: Small (1 line change)
- **Risk**: None

### Option C: Accept as-is
- The PR body justifies it as "retains edit access for troubleshooting"
- `ModifyAllData` makes it moot either way
- **Pros**: No change needed
- **Cons**: Semantic inconsistency with documented intent persists
- **Effort**: None
- **Risk**: None (functionally identical)

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `create-license/main/default/profiles/Admin.profile-meta.xml` (lines 46-95)
- **Components**: Admin profile, Replicated_Instance__c FLS

## Acceptance Criteria

- [ ] Admin profile `editable` value for Replicated_Instance__c fields reflects agreed decision
- [ ] If changed, documentation in `docs/solutions/security-issues/missing-field-level-security-configuration.md` updated to match

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-16 | Created from code review of PR #25 | 3 of 4 agents flagged this; functionally moot due to ModifyAllData |

## Resources

- PR #25: https://github.com/crdant/replicated-salesforce-fulfillment/pull/25
- Issue #20: Field-level security requirement
- CLAUDE.md: Documents Replicated_Instance__c as "read-only in SF"
