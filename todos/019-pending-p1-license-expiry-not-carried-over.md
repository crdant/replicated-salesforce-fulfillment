---
status: pending
priority: p1
issue_id: "019"
tags:
  - code-review
  - data-integrity
  - lead-conversion
dependencies: []
---

# Replicated_License_Expiry__c not carried over during Lead conversion

## Problem Statement

`AssetDownloadedHandler.convertLead()` copies `Replicated_License_Type__c` and `Replicated_Channel__c` from the Lead to the Account after conversion, but does NOT copy `Replicated_License_Expiry__c`. This field was set by `CustomerCreatedHandler` during Lead enrichment. The expiry date is silently lost during conversion.

This finding was identified by 2 agents: security-sentinel and agent-native-reviewer.

## Findings

- **Security Sentinel**: Lines 66-71 of `AssetDownloadedHandler.cls` carry over two of three enrichment fields. `Replicated_License_Expiry__c` is missing. This is a data loss bug.
- **Agent-Native Reviewer**: If downstream automation or agents need to know when the trial expires, the data won't be on the Account.

## Proposed Solutions

### Option A: Add the carry-over line (Recommended)
- Add `acc.Replicated_License_Expiry__c = lead.Replicated_License_Expiry__c;` after the existing carry-over lines
- No null check needed — Date fields handle null assignment gracefully
- **Pros**: Simple 1-line fix; completes the data carry-over
- **Cons**: None
- **Effort**: Small (1 line)
- **Risk**: None

### Option B: Use Lead field mapping (auto-mapping)
- Configure Lead-to-Account field mapping in Salesforce Setup so conversion auto-maps the fields
- **Pros**: No code needed; works for any future conversions
- **Cons**: Field mapping is org configuration, not source-controlled; may require `Account.Replicated_License_Expiry__c` field to exist (needs verification)
- **Effort**: Small (configuration)
- **Risk**: Low — but harder to track in version control

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `create-license/main/default/classes/AssetDownloadedHandler.cls` (line ~71)
- **Components**: Lead conversion, Account enrichment

## Acceptance Criteria

- [ ] `Replicated_License_Expiry__c` is present on the Account after Lead conversion
- [ ] Test verifies expiry date carry-over (update `AssetDownloadedHandlerTest.testConvertsLeadToAccountContactOpportunity`)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | 2 agents flagged this; simple data loss bug |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
