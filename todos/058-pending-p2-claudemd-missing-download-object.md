---
status: complete
priority: p2
issue_id: "058"
tags:
  - code-review
  - documentation
  - agent-native
dependencies: []
---

# Add Replicated_Download__c to CLAUDE.md Key Salesforce Objects

## Problem Statement

`CLAUDE.md` documents key Salesforce objects in the project but does not include the new `Replicated_Download__c` object. Agents reading `CLAUDE.md` for data model context will not know this object exists, what it tracks, or how it relates to other objects. This is a context parity gap.

## Findings

**File:** `CLAUDE.md`, "Key Salesforce Objects" section

Current entries:
- `Product2`, `Order.LicenseId__c`, `Replicated_Instance__c`, `Replicated_Webhook__e`, `Replicated_Webhook_Secret__mdt`

Missing: `Replicated_Download__c` and `Order.FulfilledAt__c`

**Raised by:** Agent-Native Reviewer

## Proposed Solutions

### Option A: Add entries for both new artifacts (Recommended)
- Add `Replicated_Download__c` with description of its purpose and relationship to Account
- Add `Order.FulfilledAt__c` alongside existing `Order.LicenseId__c` entry
- **Effort**: Small (2-3 lines in CLAUDE.md)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `CLAUDE.md` "Key Salesforce Objects" section includes `Replicated_Download__c`
- [ ] `Order.FulfilledAt__c` is mentioned (either as separate entry or alongside `LicenseId__c`)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #88 | Agent-native parity requires documenting all schema objects |

## Resources

- PR #88: Adds Replicated_Download__c object and Order.FulfilledAt__c field
- CLAUDE.md: Key Salesforce Objects section
