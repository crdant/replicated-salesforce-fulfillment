---
status: deferred
priority: p2
issue_id: "057"
tags:
  - code-review
  - architecture
  - salesforce
  - schema
dependencies: []
---

# Evaluate adding Order__c Lookup on Replicated_Download__c

## Problem Statement

`Replicated_Download__c` tracks download events that drive `Order.FulfilledAt__c` fulfillment, but there is no direct relationship from a download record to the Order it fulfilled. The fulfillment workflow must resolve the mapping through Account -> Order traversal, which is indirect and ambiguous when an Account has multiple Orders.

## Findings

**Raised by:** Architecture Strategist

The `AssetDownloadedHandler` (to be revised in #85) will need to:
1. Receive a download event with `customer_id` and `license_type`
2. Find the Account via `Replicated_Customer_Id__c`
3. Find the unfulfilled Order on that Account
4. Set `Order.FulfilledAt__c`
5. Create a `Replicated_Download__c` record

Without a direct Download-to-Order Lookup, step 5 creates a record with no link back to the Order from step 4. Reporting and audit trails lose the direct association.

## Proposed Solutions

### Option A: Add optional Order__c Lookup now (Recommended if #85 needs it)
- Add `Order__c` Lookup field (optional, nullable) to `Replicated_Download__c`
- Allows direct navigation from download to fulfilled Order
- Simplifies reporting and audit queries
- **Effort**: Small (field XML + FLS entries + package.xml)
- **Risk**: Low — nullable Lookup has no deployment risk

### Option B: Defer to #85 handler implementation
- Let the handler PR determine whether the relationship is needed based on actual logic
- Avoids speculative schema if the handler resolves fulfillment without needing the link
- **Effort**: None now
- **Risk**: Low — may require a follow-up schema change

### Option C: No relationship needed
- Downloads are independent audit records; Order fulfillment is tracked via `FulfilledAt__c` timestamp
- The temporal correlation (download timestamp = fulfillment timestamp) is sufficient
- **Effort**: None
- **Risk**: Weaker audit trail

## Recommended Action

<!-- Fill during triage — depends on #85 handler design -->

## Acceptance Criteria

- [ ] Design decision documented: whether Order__c Lookup is needed
- [ ] If yes: field XML, FLS across 6 profiles, package.xml updated
- [ ] If no: rationale documented for future reference

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #88 | Handler logic in #85 will determine if direct link is needed |

## Resources

- PR #88: Adds Replicated_Download__c object
- Issue #85: AssetDownloadedHandler revision (depends on this schema)
- Issue #86: EpUserJoinedHandler (depends on this schema)
