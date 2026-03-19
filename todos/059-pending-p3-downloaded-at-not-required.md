---
status: complete
priority: p3
issue_id: "059"
tags:
  - code-review
  - architecture
  - salesforce
  - schema
dependencies: []
---

# Consider making Downloaded_At__c required

## Problem Statement

`Replicated_Download__c.Downloaded_At__c` is `required=false`, but a download record without a timestamp is semantically incomplete. The webhook payload from Replicated always includes a `downloaded_at` timestamp. Making it required would enforce data integrity at the platform level.

## Findings

**File:** `create-license/main/default/objects/Replicated_Download__c/fields/Downloaded_At__c.field-meta.xml`

```xml
<required>false</required>
```

**Raised by:** Architecture Strategist

**Trade-off:** Setting `required=true` would remove the field from profile FLS entries (per Salesforce rules and documented pattern in `salesforce-fls-required-field-deployment-rejection.md`). This is acceptable since the field is system-populated, but changes the FLS surface area.

## Proposed Solutions

### Option A: Set required=true
- Enforces data integrity at the platform level
- Removes need for FLS entries (simplifies profiles)
- **Effort**: Small (field XML change + remove FLS entries from 6 profiles)
- **Risk**: Low

### Option B: Leave as optional (Current)
- Handler code is responsible for always populating the field
- FLS entries remain in profiles for visibility control
- **Effort**: None
- **Risk**: Low — handler should always populate it

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Design decision documented
- [ ] If required: update field XML, remove FLS entries from all 6 profiles
- [ ] If optional: no changes needed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #88 | Required fields cannot have FLS entries per Salesforce rules |

## Resources

- PR #88: Adds Replicated_Download__c object
- `docs/solutions/build-errors/salesforce-fls-required-field-deployment-rejection.md`
