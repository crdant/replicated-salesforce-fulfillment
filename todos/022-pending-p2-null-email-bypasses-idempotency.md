---
status: pending
priority: p2
issue_id: "022"
tags:
  - code-review
  - data-integrity
  - idempotency
dependencies: []
---

# Null email bypasses idempotency in TrialSignupHandler

## Problem Statement

When `email` is null or blank, `TrialSignupHandler` skips the duplicate check entirely (line 16). Every webhook replay with a blank email creates a new duplicate Lead with `LastName = 'Unknown'`, `Company = 'Unknown'`. These orphan Leads have no deduplication key and cannot be correlated with later `customer.created` or `asset.downloaded` events.

Platform Events provide at-least-once delivery, so replays are expected.

This finding was identified by security-sentinel.

## Findings

- **Security Sentinel**: Finding #4 (MEDIUM) — blank-email signups produce unbounded duplicate Leads. No alternative dedup key exists.
- **Architecture Strategist**: Race condition between simultaneous signup and customer.created events can also produce duplicates. A database-level duplicate rule would be a safety net.

## Proposed Solutions

### Option A: Reject blank-email signups (Recommended)
- Early return with debug log if email is blank
- The trial pipeline depends on email for cross-event correlation (CustomerCreatedHandler looks up Leads by email)
- **Pros**: Prevents orphan Leads; pipeline integrity preserved
- **Cons**: May miss legitimate signups without email (unlikely for self-service trial)
- **Effort**: Small (2 lines)
- **Risk**: Low

### Option B: Add an alternative dedup key
- Use a unique signup ID from the webhook payload (if available) as a `Replicated_Signup_Id__c` external ID
- **Pros**: Handles the rare case of legitimate blank-email signups
- **Cons**: Requires new custom field; depends on Replicated payload containing a unique signup ID
- **Effort**: Medium
- **Risk**: Low

### Option C: Add a Salesforce duplicate rule on Lead
- Database-level protection against duplicate Leads based on email or other compound key
- **Pros**: Catches duplicates from all sources (not just this handler)
- **Cons**: Org-level configuration, not source-controlled; may affect other Lead creation flows
- **Effort**: Small (configuration)
- **Risk**: Low-Medium

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `create-license/main/default/classes/TrialSignupHandler.cls` (lines 16-26)

## Acceptance Criteria

- [ ] Blank-email signups either rejected or deduplicated
- [ ] Test covers the chosen behavior

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | Pipeline depends on email for cross-event correlation |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
