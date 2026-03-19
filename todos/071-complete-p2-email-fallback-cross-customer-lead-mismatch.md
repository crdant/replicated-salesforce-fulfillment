---
status: complete
priority: p2
issue_id: "071"
tags:
  - code-review
  - data-integrity
  - apex
  - security
dependencies: []
---

# Email fallback can convert a Lead belonging to a different customer

## Problem Statement

When a Lead is not found by `customer_id`, the handler falls back to email lookup (lines 108-111). If the email-matched Lead already has a different `Replicated_Customer_Id__c` set, the handler converts that Lead under the wrong customer. The converted Account then gets stamped with the event's `customer_id`, severing the Lead's original customer association.

This is a data integrity issue, not an exploitable vulnerability (webhook payloads are HMAC-authenticated). But a legitimate `customer.ep_user_joined` event where the email coincidentally matches a Lead from a different customer's trial signup would silently misattribute the conversion.

## Findings

- **Security Sentinel**: Flagged as Medium severity. The email-matched Lead could belong to a completely different Replicated customer. Recommended guarding against non-blank `Replicated_Customer_Id__c` on the email-matched Lead.
- **Architecture Strategist**: Flagged as Medium. Also noted the `Map<String, Lead>` keyed by email silently overwrites when multiple Leads share the same email (no `ORDER BY`).
- **Learnings Researcher**: `docs/solutions/integration-issues/lead-conversion-custom-field-mapping-and-fallback-lookup.md` documents the email fallback pattern but doesn't address the cross-customer guard.

## Proposed Solutions

### Option A: Guard email fallback — only match Leads with blank customer ID (Recommended)

```apex
Lead lead = leadsByCustomerId.get(customerId);
if (lead == null && String.isNotBlank(joinedEmail)) {
    Lead emailLead = leadsByEmail.get(joinedEmail);
    // Only use email fallback if Lead has no conflicting customer ID
    if (emailLead != null && String.isBlank(emailLead.Replicated_Customer_Id__c)) {
        lead = emailLead;
    }
}
```

- Pros: Prevents cross-customer misattribution; matches the documented intent (email fallback is for Leads created by `TrialSignupHandler` before customer ID exists)
- Cons: None
- Effort: Small
- Risk: None — the fallback query already selects `Replicated_Customer_Id__c`

### Option B: Also add ORDER BY to the email query

Add `ORDER BY CreatedDate DESC` to the email fallback SOQL to deterministically select the most recent Lead when duplicates exist.

- Pros: Handles the multi-Lead-per-email edge case
- Cons: Marginal improvement for a rare scenario
- Effort: Small
- Risk: None

## Recommended Action

Option A, optionally combined with Option B.

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandler.cls` lines 108-111
- **Affected components**: Lead lookup logic in webhook handler
- **Database changes**: None

## Acceptance Criteria

- [ ] Email fallback only matches Leads with blank `Replicated_Customer_Id__c`
- [ ] Add test: Lead with a different customer's `Replicated_Customer_Id__c` is NOT matched by email
- [ ] Existing `testLeadLookupFallsBackToEmail` continues to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — security sentinel + architecture strategist |

## Resources

- PR: #91
- File: `EpUserJoinedHandler.cls` lines 108-111
- Related: `docs/solutions/integration-issues/lead-conversion-custom-field-mapping-and-fallback-lookup.md`
