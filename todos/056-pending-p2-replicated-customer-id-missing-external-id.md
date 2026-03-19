---
status: complete
priority: p2
issue_id: "056"
tags:
  - code-review
  - architecture
  - salesforce
  - schema
dependencies: []
---

# Mark Replicated_Customer_Id__c as externalId on Replicated_Download__c

## Problem Statement

`Replicated_Download__c.Replicated_Customer_Id__c` has `externalId=false`, but the project's architectural reconciliation key is `custom_id` (Replicated) = Salesforce Account ID. Existing objects follow a pattern of `externalId=true` on reconciliation fields: `Account.Replicated_Customer_Id__c` and `Replicated_Instance__c.Instance_Id__c` both have `externalId=true`. Without the external ID flag, the field is not indexed — SOQL queries filtering by customer ID will degrade as the table grows. Downstream handlers (#85, #86) will likely query downloads by customer ID.

## Findings

**File:** `create-license/main/default/objects/Replicated_Download__c/fields/Replicated_Customer_Id__c.field-meta.xml`

```xml
<externalId>false</externalId>
```

**Raised by:** Security Sentinel (dedup/integrity concern), Architecture Strategist (indexed query concern)

Note: `unique=false` is correct since one customer can have many downloads — only `externalId` needs to change.

## Proposed Solutions

### Option A: Set externalId=true (Recommended)
- Change `<externalId>false</externalId>` to `<externalId>true</externalId>`
- Keep `<unique>false</unique>` (many downloads per customer)
- Provides Salesforce-managed index for `WHERE Replicated_Customer_Id__c = :id` queries
- Consistent with `Account.Replicated_Customer_Id__c` and `Replicated_Instance__c.Instance_Id__c` patterns
- **Effort**: Small (one XML element change)
- **Risk**: None

### Option B: Defer to handler PRs (#85/#86)
- Leave as-is and address when the handler logic is defined
- Risk of forgetting; requires a follow-up schema migration after records exist
- **Effort**: None now, Small later
- **Risk**: Low — but adds future migration complexity

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `Replicated_Customer_Id__c.field-meta.xml` has `<externalId>true</externalId>`
- [ ] `<unique>false</unique>` remains unchanged
- [ ] `make deploy` succeeds

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #88 | Existing objects use externalId=true on reconciliation fields |

## Resources

- PR #88: Adds Replicated_Download__c object
- Existing pattern: `Replicated_Instance__c.Instance_Id__c` (`externalId=true`, `unique=true`)
- CLAUDE.md: "`custom_id` as reconciliation key"
