---
title: "Trial Lifecycle Handler Bulkification: Resolving Queueable Governor Limit"
category: integration-issues
date: 2026-03-18
tags:
  - salesforce
  - apex
  - governor-limits
  - bulkification
  - platform-events
  - queueable
  - lead-conversion
  - trial-lifecycle
components:
  - TrialSignupHandler.cls
  - CustomerCreatedHandler.cls
  - AssetDownloadedHandler.cls
  - ReplicatedWebhookSubscriber.trigger
severity: high
time_to_resolve: 2-3 hours
related_pr: 50
---

# Trial Lifecycle Handler Bulkification

## Problem

Three new trial lifecycle event handlers (`TrialSignupHandler`, `CustomerCreatedHandler`, `AssetDownloadedHandler`) were implemented with per-event Queueable enqueue calls in the `ReplicatedWebhookSubscriber` trigger. Salesforce Platform Event triggers can receive up to 2,000 events per batch, but the Queueable governor limit is 50 `System.enqueueJob()` calls per transaction. With per-event enqueue, any batch exceeding 50 events of the same type would hit a `LimitException`.

A secondary issue: `AssetDownloadedHandler` converted Leads to Accounts but did not carry over `Replicated_License_Expiry__c`, losing the trial expiration date during conversion.

## Root Cause

The initial implementation followed a one-event-one-job pattern:

```apex
// BEFORE: per-event enqueue in the trigger (broken at scale)
for (Replicated_Webhook__e event : Trigger.New) {
    if (event.Event_Type__c == 'Pending Self-Service Signup') {
        System.enqueueJob(new TrialSignupHandler(event));
    }
}
```

Each handler accepted a single event and performed its own SOQL queries and DML. With N events of the same type, this produced N Queueable jobs and N*M SOQL queries -- hitting both the 50-job limit and the 100-SOQL limit.

The existing `InstanceEventHandler` and `LicenseExpiringHandler` (merged in PR #51) had already adopted a batched pattern: the trigger collects events into typed lists and enqueues one handler per type. The three new handlers did not follow this pattern.

## Investigation

1. Reviewed the batched pattern in `InstanceEventHandler` and `LicenseExpiringHandler` from main branch (PR #51).
2. Confirmed the trigger routes 5 event types, meaning at most 5 `System.enqueueJob()` calls per transaction -- well within the 50-job limit.
3. Identified that all three handlers needed:
   - Constructor accepting `List<Replicated_Webhook__e>` instead of a single event
   - Bulk SOQL with `WHERE field IN :collection` patterns
   - Bulk DML with list-based `insert`/`update`
   - Within-batch deduplication (especially for email-keyed Lead lookups)

## Solution

### Trigger: Collect events by type, enqueue one job per handler

```apex
trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    List<Replicated_Webhook__e> signupEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> customerCreatedEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> assetDownloadedEvents = new List<Replicated_Webhook__e>();
    // ... other event types

    for (Replicated_Webhook__e event : Trigger.New) {
        if (String.isBlank(event.Payload__c)) { continue; }
        switch on event.Event_Type__c {
            when 'Pending Self-Service Signup' { signupEvents.add(event); }
            when 'customer.created' { customerCreatedEvents.add(event); }
            when 'Release Assets Downloaded' { assetDownloadedEvents.add(event); }
            // ...
        }
    }

    if (!signupEvents.isEmpty()) { System.enqueueJob(new TrialSignupHandler(signupEvents)); }
    if (!customerCreatedEvents.isEmpty()) { System.enqueueJob(new CustomerCreatedHandler(customerCreatedEvents)); }
    if (!assetDownloadedEvents.isEmpty()) { System.enqueueJob(new AssetDownloadedHandler(assetDownloadedEvents)); }
}
```

Maximum 5 enqueue calls regardless of batch size.

### TrialSignupHandler: Bulk Lead creation with within-batch dedup

Key pattern -- collect all emails first, bulk-query existing Leads, then deduplicate within the batch using a running set:

```apex
Set<String> existingEmails = new Set<String>();
for (Lead l : [SELECT Email FROM Lead WHERE Email IN :emails AND IsConverted = false]) {
    existingEmails.add(l.Email);
}

List<Lead> toInsert = new List<Lead>();
for (Map<String, Object> data : dataList) {
    String email = (String) data.get('email');
    if (String.isNotBlank(email) && existingEmails.contains(email)) { continue; }
    toInsert.add(new Lead(/* ... */));
    if (String.isNotBlank(email)) { existingEmails.add(email); } // within-batch dedup
}
if (!toInsert.isEmpty()) { insert toInsert; }
```

### CustomerCreatedHandler: Bulk Lead enrichment and creation

Splits into two DML operations: update existing Leads and insert new ones. Uses safe date parsing with try-catch (matching `LicenseExpiringHandler` pattern):

```apex
Date expiryDate = null;
if (String.isNotBlank(expiresAt)) {
    try {
        expiryDate = Date.valueOf(expiresAt.substring(0, 10));
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'CustomerCreatedHandler: invalid expires_at: ' + expiresAt);
    }
}
```

### AssetDownloadedHandler: Bulk Lead conversion with field carry-over

Uses `Database.convertLead()` with a list of `Database.LeadConvert` objects. Post-conversion enrichment carries over all Replicated fields including the previously missing expiry:

```apex
Lead lead = leads[i];
Account acc = new Account(Id = result.getAccountId(), Replicated_Customer_Id__c = customerIds[i]);
if (String.isNotBlank(lead.Replicated_License_Type__c)) {
    acc.Replicated_License_Type__c = lead.Replicated_License_Type__c;
}
if (String.isNotBlank(lead.Replicated_Channel__c)) {
    acc.Replicated_Channel__c = lead.Replicated_Channel__c;
}
if (lead.Replicated_License_Expiry__c != null) {
    acc.Replicated_License_Expiry__c = lead.Replicated_License_Expiry__c;
}
```

Direct-create path (no Lead exists) uses `Database.setSavepoint()` / `Database.rollback()` for atomicity across the three-phase Account + Contact + Opportunity creation.

## Prevention

### Batch Processing Checklist for New Handlers

- [ ] Handler constructor accepts `List<Replicated_Webhook__e>`, never a single event
- [ ] Trigger collects events by type and enqueues one job per handler type
- [ ] All SOQL uses `WHERE field IN :collection` (set-based), never per-record queries
- [ ] All DML operates on lists, never individual records
- [ ] Within-batch deduplication uses a running `Set<String>` for the key field
- [ ] `SyncGuard.inboundSyncIds.add()` is called for all created/updated record IDs

### Field Carry-Over Checklist for Lead Conversion

When converting Leads to Accounts, verify that all custom fields set on the Lead are explicitly copied to the Account in the post-conversion enrichment step. Standard Lead conversion only maps fields configured in Salesforce Lead Field Mapping -- custom Replicated fields require manual carry-over.

- [ ] `Replicated_Customer_Id__c`
- [ ] `Replicated_License_Type__c`
- [ ] `Replicated_Channel__c`
- [ ] `Replicated_License_Expiry__c`

### Code Review Checklist

- [ ] Count `System.enqueueJob()` calls -- must be bounded (not proportional to input size)
- [ ] Count SOQL queries -- should not scale with event count
- [ ] Verify `without sharing` declaration on system-to-system webhook handlers
- [ ] Check for savepoint/rollback on multi-object DML sequences
- [ ] Verify all enrichment fields are carried over during Lead conversion

## Cross-References

- [Bidirectional Sync Loop Prevention](bidirectional-sync-loop-prevention.md) -- SyncGuard pattern used by all handlers
- [Webhook Receiver HMAC Verification](webhook-receiver-hmac-verification.md) -- upstream webhook ingestion
- `docs/research/2026-03-16-event-driven-bidirectional-sync.md` -- architectural research
- PR #51 -- established the batched handler pattern with `InstanceEventHandler` and `LicenseExpiringHandler`
- PR #50 -- implements the three trial lifecycle handlers with bulkification fixes
