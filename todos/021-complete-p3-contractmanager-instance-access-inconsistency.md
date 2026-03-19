---
status: complete
priority: p3
issue_id: "021"
tags:
  - code-review
  - security
  - field-level-security
  - ux
dependencies: []
---

# ContractManager has Replicated_Instance__c object access but minimal field visibility

## Problem Statement

The PR adds `objectPermissions` for `Replicated_Instance__c` with `allowRead=true` and `viewAllRecords=true` to the ContractManager profile. However, only `Status__c` is `readable=true` for ContractManager — all other 7 Replicated_Instance__c fields are `readable=false`. This creates a confusing UX where ContractManager users can see Instance records but only the Status field has data.

If ContractManager should have no Replicated access, the objectPermissions block should be removed. If they need instance visibility, more fields should be readable.

## Findings

- **Security Sentinel**: Medium severity. Object-level access with minimal field visibility is an odd pattern. Confirm whether ContractManager should see instances at all.
- **Pattern Recognition Specialist**: ContractManager is the only profile with this "object access but almost no field access" pattern.

## Proposed Solutions

### Option A: Remove objectPermissions for ContractManager

If ContractManager doesn't need instance data, remove the `objectPermissions` block from `ContractManager.profile-meta.xml`.

- **Pros**: Clean separation — no access means no confusing blank records
- **Cons**: ContractManager loses ability to see even instance Status
- **Effort**: Small (remove 9 XML lines)
- **Risk**: Low

### Option B: Keep as-is and document the intent

If Status__c alone is sufficient (e.g., a "heartbeat" indicator), document why ContractManager gets this limited access.

- **Pros**: No code change needed
- **Cons**: Inconsistency remains undocumented
- **Effort**: None
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected file**: `create-license/main/default/profiles/ContractManager.profile-meta.xml`
- **objectPermissions**: lines 134-142 (new in this PR)
- **Status__c FLS**: line 127-130 (`readable=true` — pre-existing)

## Acceptance Criteria

- [ ] Decision made on whether ContractManager needs Replicated_Instance__c access
- [ ] Either objectPermissions removed or intent documented

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #52 | Security sentinel and pattern recognition flagged |

## Resources

- PR #52: https://github.com/crdant/replicated-salesforce-fulfillment/pull/52
