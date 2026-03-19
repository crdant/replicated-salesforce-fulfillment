---
status: complete
priority: p2
issue_id: "027"
tags:
  - code-review
  - architecture
  - sync-guard
  - bidirectional-sync
dependencies: []
---

# SyncGuard set after insert (latent defect) and missing on Contact/Opportunity

## Problem Statement

Two related issues with SyncGuard usage:

1. **Timing**: All `insert` operations add to `SyncGuard.inboundSyncIds` AFTER the DML. Since triggers fire synchronously during insert, any `after insert` trigger on the object will run WITHOUT SyncGuard protection. The project's own documentation in `bidirectional-sync-loop-prevention.md` explicitly warns: "Adding the ID after the DML. The trigger fires synchronously during the update call."

2. **Missing guards**: `AssetDownloadedHandler.createAccountContactOpportunity()` adds SyncGuard for the Account but NOT for the Contact or Opportunity. The `convertLead()` path also only guards the Account, not the converted Contact/Opportunity. The documentation warns: "Not guarding related-object triggers."

Not exploitable today (no outbound triggers on Lead, Contact, or Opportunity), but a latent defect that will cause sync loops when outbound triggers are added.

This finding was identified by 3 agents: security-sentinel, architecture-strategist, and learnings-researcher.

## Findings

- **Architecture Strategist**: "The project's own documentation lists this as an explicit anti-pattern in two places"
- **Learnings Researcher**: `bidirectional-sync-loop-prevention.md` says "Add IDs to SyncGuard.inboundSyncIds BEFORE DML, never after"
- **Security Sentinel**: Finding #5 (LOW) — latent timing gap on inserts

## Proposed Solutions

### Option A: Add SyncGuard for all objects + document the insert gap (Recommended)
- Add `SyncGuard.inboundSyncIds.add()` for Contact and Opportunity after their inserts
- Add code comments at each insert site explaining the structural limitation for new records
- For `update` operations, verify guard is set before DML (already correct)
- **Pros**: Complete guard coverage; documented limitation
- **Cons**: Insert gap remains (structurally unavoidable for new records)
- **Effort**: Small
- **Risk**: None

### Option B: Restructure SyncGuard to use external IDs
- Guard using `Replicated_Customer_Id__c` (known before insert) instead of Salesforce IDs
- Outbound triggers check the external ID in SyncGuard instead of the record ID
- **Pros**: Eliminates the insert timing gap entirely
- **Cons**: Requires changing SyncGuard contract and all outbound trigger checks
- **Effort**: Medium-Large
- **Risk**: Medium — changes the SyncGuard interface project-wide

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: All 3 handler classes
- **Specific locations**:
  - `TrialSignupHandler.cls` lines 37-38 (insert Lead, guard after)
  - `CustomerCreatedHandler.cls` lines 60-61 (insert Lead, guard after)
  - `AssetDownloadedHandler.cls` lines 87-88 (insert Account, guard after)
  - `AssetDownloadedHandler.cls` lines 95, 103 (insert Contact/Opportunity, NO guard)

## Acceptance Criteria

- [ ] Contact and Opportunity inserts in AssetDownloadedHandler have SyncGuard
- [ ] All insert sites have a code comment explaining the timing limitation
- [ ] Update operations confirm guard-before-DML ordering

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | Project docs explicitly warn about both issues |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
- `docs/solutions/integration-issues/bidirectional-sync-loop-prevention.md`
