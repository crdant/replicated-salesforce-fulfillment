---
status: pending
priority: p2
issue_id: "003"
tags:
  - code-review
  - security
  - field-level-security
  - follow-up
dependencies: []
---

# Missing FLS for Account, Lead, and Product2 custom fields

## Problem Statement

The same FLS gap this PR fixes for `Replicated_Instance__c` exists for other custom objects:

- **Account** (4 fields, 0 fieldPermissions): `Last_Synced_By__c`, `Replicated_Customer_Id__c`, `Replicated_Channel__c`, `Replicated_License_Type__c`
- **Lead** (2 fields, 0 fieldPermissions): `Replicated_Customer_Id__c`, `Replicated_License_Expiry__c`
- **Product2** (8 field definitions, only 5 fieldPermissions): Missing `Application__c`, `IsSnapshotSupported__c`, `IsSupportBundleUploadEnabled__c`

This PR's own prevention guidance states: "FLS must ship in the same PR as field definitions. Never defer FLS to a follow-up." Applying that principle retroactively reveals these gaps.

## Findings

- **Architecture Strategist**: Account and Lead fields from PR #15 have no fieldPermissions in any profile. Same gap class as issue #20.
- **Agent-Native Reviewer**: Product2 has 8 field definitions but only 5 fieldPermissions (3 missing). Account (4 fields) and Lead (2 fields) have zero fieldPermissions.

## Proposed Solutions

### Option A: Create follow-up GitHub issue (Recommended)
- Open a new issue tracking the 9 missing FLS entries across 3 objects
- Apply the same pattern established in PR #25
- **Pros**: Keeps PR #25 focused, tracks the work
- **Cons**: Gap persists until follow-up is implemented
- **Effort**: Small (issue creation)
- **Risk**: Low — these are pre-existing gaps

### Option B: Expand PR #25 scope
- Add the missing FLS entries to this PR
- **Pros**: Closes all FLS gaps at once
- **Cons**: Scope creep on an otherwise clean PR
- **Effort**: Medium (9 fields across 6 profiles = 54 more XML blocks)
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Missing Account fields**: `Last_Synced_By__c`, `Replicated_Customer_Id__c`, `Replicated_Channel__c`, `Replicated_License_Type__c`
- **Missing Lead fields**: `Replicated_Customer_Id__c`, `Replicated_License_Expiry__c`
- **Missing Product2 fields**: `Application__c`, `IsSnapshotSupported__c`, `IsSupportBundleUploadEnabled__c`
- **Affected profiles**: All 6

## Acceptance Criteria

- [ ] Follow-up issue created OR FLS entries added to this PR
- [ ] All custom fields across all objects have corresponding fieldPermissions in all profiles

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-16 | Created from code review of PR #25 | architecture-strategist and agent-native-reviewer independently found this |

## Resources

- PR #25: https://github.com/crdant/replicated-salesforce-fulfillment/pull/25
- Prevention guidance: `docs/solutions/security-issues/missing-field-level-security-configuration.md` lines 105-130
