---
status: pending
priority: p3
issue_id: "027"
tags:
  - code-review
  - architecture
  - data-integrity
  - race-condition
dependencies: []
---

# Duplicate Lead race condition from parallel Queueable execution

## Problem Statement

If `signup` and `customer.created` events for the same email arrive near-simultaneously, they are processed by parallel Queueable jobs. Both `TrialSignupHandler` and `CustomerCreatedHandler` could find no existing Lead (each queries before the other inserts) and both create a Lead for the same email. This produces duplicate Leads.

Low-probability edge case in current architecture, but possible with Platform Event at-least-once delivery and parallel Queueable execution.

This finding was identified by 2 agents: architecture-strategist and performance-oracle.

## Findings

- **Architecture Strategist**: "If signup and customer.created arrive nearly simultaneously and are processed in parallel Queueable jobs, both could find no existing Lead and both insert one."
- **Performance Oracle**: "If two Queueable jobs execute concurrently for the same email, both could pass the duplicate check before either inserts."

## Proposed Solutions

### Option A: Add a Salesforce Duplicate Rule on Lead (Recommended)
- Database-level protection that catches duplicates from any source
- **Pros**: Catches all duplicate scenarios; standard Salesforce feature
- **Cons**: Org-level configuration; may affect other Lead creation flows
- **Effort**: Small (configuration)
- **Risk**: Low

### Option B: Make Lead.Replicated_Customer_Id__c unique
- Enforces uniqueness at the field level once customer ID is set
- **Pros**: Prevents duplicate customer IDs
- **Cons**: Only helps after CustomerCreatedHandler enriches the Lead; doesn't prevent duplicate signups (which don't have customer ID)
- **Effort**: Small
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: No code change needed for Option A (Salesforce configuration)
- **Related handlers**: TrialSignupHandler, CustomerCreatedHandler

## Acceptance Criteria

- [ ] Concurrent creation of Leads with same email results in at most one Lead
- [ ] Duplicate detection handles both signup and customer.created paths

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | Low probability but real risk |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
