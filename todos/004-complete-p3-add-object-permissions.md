---
status: complete
priority: p3
issue_id: "004"
tags:
  - code-review
  - security
  - defense-in-depth
dependencies: []
---

# Add objectPermissions for Replicated_Instance__c to enforce read-only at object level

## Problem Statement

No profile contains `<objectPermissions>` for `Replicated_Instance__c`. While `fieldPermissions` control field access and the object's `sharingModel=Read` restricts sharing, explicit object permissions would enforce read-only CRUD access as defense-in-depth.

## Findings

- **Security Sentinel**: Object-level permissions would make the "read-only in SF" intent explicit and enforceable. Currently relying on org defaults + sharing model.

## Proposed Solutions

### Option A: Add objectPermissions to all non-Admin profiles
```xml
<objectPermissions>
    <allowCreate>false</allowCreate>
    <allowDelete>false</allowDelete>
    <allowEdit>false</allowEdit>
    <allowRead>true</allowRead>
    <modifyAllRecords>false</modifyAllRecords>
    <object>Replicated_Instance__c</object>
    <viewAllRecords>true</viewAllRecords>
</objectPermissions>
```
- **Effort**: Small (add to 5 profiles)
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] objectPermissions entries exist for Replicated_Instance__c in all non-Admin profiles

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-16 | Created from code review of PR #25 | Defense-in-depth recommendation from security-sentinel |

## Resources

- PR #25: https://github.com/crdant/replicated-salesforce-fulfillment/pull/25
