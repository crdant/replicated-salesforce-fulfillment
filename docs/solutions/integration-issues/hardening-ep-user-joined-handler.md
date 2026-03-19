---
title: "EpUserJoinedHandler defensive coding hardening"
category: integration-issues
severity: p2
date: 2026-03-19
tags:
  - defensive-coding
  - error-handling
  - data-integrity
  - batch-safety
  - type-safety
  - apex
  - webhook-handler
  - lead-conversion
  - code-review
related_files:
  - create-license/main/default/classes/EpUserJoinedHandler.cls
  - create-license/main/default/classes/EpUserJoinedHandlerTest.cls
related_issues:
  - 91
  - 96
  - 97
---

# Hardening EpUserJoinedHandler

Multi-agent code review of `EpUserJoinedHandler` (PR #91) identified four P2 defensive-coding gaps. All four were fixed in the same PR with three new test methods. 68/68 org tests pass at 100%.

## Problem

The handler processes `customer.ep_user_joined` webhook events to convert Leads into Account/Contact/Opportunity on first Enterprise Portal login. Four issues could cause batch failures, data integrity corruption, or silent data loss under edge-case payload conditions:

1. **Boolean cast outside try/catch** killed the entire batch if `is_first_user` arrived as a non-boolean type
2. **Email fallback lookup** could convert a Lead belonging to a different Replicated customer
3. **Missing customer_id validation** allowed Accounts to be created without the reconciliation key
4. **All-or-nothing DML** on Account enrichment meant one failure rolled back all enrichments

## Root Cause

### 1. Unguarded boolean cast (line 33)

The `is_first_user` field was accessed via `(Boolean)` cast outside the try/catch block that wraps `JSON.deserializeUntyped()`. `JSON.deserializeUntyped()` preserves JSON booleans as Apex `Boolean`, but if the Replicated API sends a String `"true"` instead, the cast throws `System.TypeException` — an unhandled exception that terminates processing of ALL remaining events in the batch.

### 2. Cross-customer email fallback (lines 108-111)

When no Lead matched by `customer_id`, the handler fell back to email lookup without verifying the matched Lead's ownership. A Lead previously enriched by `CustomerCreatedHandler` with a different `Replicated_Customer_Id__c` would be converted under the wrong customer, severing the original association and corrupting the reconciliation key.

### 3. Null customer_id passes idempotency (line 99)

`data.get('customer_id')` cast to String without null/blank check. A null `customerId` passes `existingAccountCustomerIds.contains(null)` (returns `false`), bypasses both Lead lookups (neither map has a null key), and falls through to the direct-create path — producing an Account with null `Replicated_Customer_Id__c`.

### 4. Bare update on enrichment (line 175)

`update toUpdate` uses Salesforce's default all-or-nothing DML. One Account enrichment failure (e.g., validation rule) blocks enrichment for all other converted Accounts in the batch.

## Solution

### Fix 1: instanceof guard on is_first_user

```apex
// Before — cast outside try/catch, crashes batch on type mismatch
Object isFirstUser = data.get('is_first_user');
if (isFirstUser == null || !(Boolean) isFirstUser) {
    continue;
}

// After — instanceof check, gracefully skips non-boolean values
Object isFirstUser = data.get('is_first_user');
if (!(isFirstUser instanceof Boolean) || !(Boolean) isFirstUser) {
    continue;
}
```

### Fix 2: Email fallback guards against cross-customer mismatch

```apex
// Before — email fallback matches any unconverted Lead
Lead lead = leadsByCustomerId.get(customerId);
if (lead == null && String.isNotBlank(joinedEmail)) {
    lead = leadsByEmail.get(joinedEmail);
}

// After — only match Leads with no existing customer ID
Lead lead = leadsByCustomerId.get(customerId);
if (lead == null && String.isNotBlank(joinedEmail)) {
    Lead emailLead = leadsByEmail.get(joinedEmail);
    if (emailLead != null && String.isBlank(emailLead.Replicated_Customer_Id__c)) {
        lead = emailLead;
    }
}
```

### Fix 3: Early skip on blank customer_id

```apex
String customerId = (String) data.get('customer_id');
if (String.isBlank(customerId)) {
    System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: blank customer_id, skipping');
    continue;
}
```

### Fix 4: Partial-success DML on enrichment

```apex
// Before — all-or-nothing
if (!toUpdate.isEmpty()) {
    update toUpdate;
}

// After — partial success with per-record logging
if (!toUpdate.isEmpty()) {
    List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
    for (Database.SaveResult sr : saveResults) {
        if (!sr.isSuccess()) {
            System.debug(LoggingLevel.ERROR,
                'EpUserJoinedHandler: Account enrichment failed');
        }
    }
}
```

### New tests

- `testNonBooleanIsFirstUserSkipped` — sends `is_first_user` as String `"true"`, verifies graceful skip
- `testEmailFallbackSkipsLeadWithDifferentCustomerId` — Lead with different customer ID is NOT matched by email
- `testBlankCustomerIdSkipped` — blank `customer_id` produces no records

## Prevention

### Webhook Handler Development Checklist

**Payload parsing:**
- [ ] All field access wrapped in try/catch or guarded with `instanceof`
- [ ] Required fields validated non-null/non-blank before processing
- [ ] Malformed events skip individually, never crash the batch
- [ ] Test with wrong-type fields (String instead of Boolean, null instead of String)

**Reconciliation key integrity:**
- [ ] Never create records without the join key (`Replicated_Customer_Id__c`)
- [ ] Skip events with blank/null reconciliation key with a warning log
- [ ] Test with missing key fields to verify no orphaned records

**Fallback lookup safety:**
- [ ] Secondary lookups only match records with blank primary key
- [ ] Test cross-entity scenarios (same email, different customer)
- [ ] Document why the fallback exists and what lifecycle gap it addresses

**DML patterns:**
- [ ] Use `Database.update(list, false)` / `Database.insert(list, false)` for partial success
- [ ] Log individual failures without payload data (no PII in debug logs)
- [ ] Reserve all-or-nothing DML for savepoint-wrapped atomic operations only

### Lessons Learned

1. **Defensive parsing is non-negotiable.** Webhook payloads are external data. Every field access is a potential failure point. The cost of an `instanceof` check is negligible compared to a batch failure.

2. **Reconciliation keys are sacred.** Without the join key, records are orphaned — stranded in Salesforce with no tie to the source system, impossible to reconcile, and vulnerable to duplicate creation on retry.

3. **Fallback lookups need guardrails.** Secondary lookups solve sync gaps but introduce cross-entity pollution risk. Only match records that don't already have the primary key set.

4. **Partial-success DML is the default for webhook handlers.** One bad record in a batch is that record's problem, not the batch's. Use `Database.update(..., false)` and inspect results.

## Related Documentation

- [Lead conversion custom field mapping and fallback lookup](lead-conversion-custom-field-mapping-and-fallback-lookup.md) — documents the two-tier lookup pattern and custom field carry-over
- [Bidirectional sync loop prevention](bidirectional-sync-loop-prevention.md) — SyncGuard patterns applied in this handler
- [Hardening customer.updated handler](hardening-customer-updated-handler.md) — same class of findings on a different handler; established the partial-success DML precedent
- [Webhook receiver security findings](../security-issues/webhook-receiver-code-review-findings.md) — upstream HMAC validation that establishes the trust boundary
- [Event type constants extraction](event-type-constants-extraction.md) — checklist for adding new event types

## Deferred Items

- [#96](https://github.com/crdant/replicated-salesforce-fulfillment/issues/96) — Truncate `customer_name` to prevent batch rollback on oversized names
- [#97](https://github.com/crdant/replicated-salesforce-fulfillment/issues/97) — Defer `LeadStatus` query until conversions are confirmed needed
