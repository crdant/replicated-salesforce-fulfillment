---
status: complete
priority: p2
issue_id: "019"
tags:
  - code-review
  - security
  - field-level-security
  - completeness
dependencies: []
---

# Missing FLS for Replicated_Instance__c.Account__c

## Problem Statement

`Replicated_Instance__c` has 10 custom fields, but only 8 have `fieldPermissions` entries in the profiles. Two fields lack FLS declarations:

- `Account__c` (Lookup to Account, `required=true`) — **NOT eligible for FLS** (deployment fails: "You cannot deploy to a required field")
- `Instance_Id__c` (Text, `required=true`, External ID) — **NOT eligible for FLS** (same constraint)

Neither field can have FLS. Salesforce rejects FLS on ALL required fields regardless of type (Lookup or otherwise). The prior documented exception for required Lookups was incorrect — deployment confirmed this.

## Findings

- **Architecture Strategist**: `Account__c` and `Instance_Id__c` are the only two Replicated_Instance__c fields without explicit FLS.
- **Learnings Researcher**: Required non-Lookup fields cannot have FLS — Salesforce rejects the deployment. `Instance_Id__c` is `required=true` + `type=Text`, confirming it must be excluded.
- **Field metadata verified**: `Account__c` is `required=true` + `type=Lookup` (eligible). `Instance_Id__c` is `required=true` + `type=Text` (ineligible).

## Proposed Solutions

### ~~Option A: Add FLS for Account__c only~~ (REJECTED)

Attempted during implementation. Deployment failed on all 6 profiles: "You cannot deploy to a required field: Replicated_Instance__c.Account__c". Salesforce rejects FLS on ALL required fields, including Lookups.

### Option B: No action — both fields are ineligible (Accepted)

Neither `Account__c` nor `Instance_Id__c` can have FLS entries. Both are required fields. The existing 8 fieldPermissions entries per profile represent complete coverage of all eligible Replicated_Instance__c fields.

- **Effort**: None
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Eligible field**: `Replicated_Instance__c.Account__c` — Lookup(Account), `required=true`, `type=Lookup`
- **Ineligible field**: `Replicated_Instance__c.Instance_Id__c` — Text, `required=true`, `type=Text` (deployment would fail)
- **Field metadata**: `create-license/main/default/objects/Replicated_Instance__c/fields/Account__c.field-meta.xml`
- **Verification**: `grep -c "Replicated_Instance__c" create-license/main/default/profiles/*.profile-meta.xml` (should show 9 per profile after fix, currently shows 8)

## Acceptance Criteria

- [ ] Add `fieldPermissions` for `Replicated_Instance__c.Account__c` to all 6 profiles
- [ ] `Instance_Id__c` confirmed excluded (required non-Lookup constraint)
- [ ] Field count for `Replicated_Instance__c` = 9 per profile (8 existing + Account__c)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #52 | Architecture strategist flagged 2 missing FLS entries |

## Resources

- PR #52: https://github.com/crdant/replicated-salesforce-fulfillment/pull/52
- Deployment constraint doc: `docs/solutions/build-errors/salesforce-fls-required-field-deployment-rejection.md`
