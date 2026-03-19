---
title: Lead Conversion Custom Field Mapping and Fallback Lookup Strategy
category: integration-issues
date: 2026-03-19
tags:
  - salesforce
  - apex
  - lead-conversion
  - custom-fields
  - webhook-handlers
  - replicated-platform
---

# Lead Conversion Custom Field Mapping and Fallback Lookup Strategy

## Problem

Two issues surfaced when implementing `EpUserJoinedHandler` for `customer.ep_user_joined` events:

1. **Custom fields lost on Lead conversion.** `Database.convertLead()` does not copy custom fields from Lead to Account. `Replicated_Customer_Id__c`, `Replicated_License_Type__c`, `Replicated_Channel__c`, and `Replicated_License_Expiry__c` all disappear from the resulting Account unless explicitly copied.

2. **Lead lookup by customer ID misses early-stage Leads.** `TrialSignupHandler` creates Leads on `customer.pending_signup` before a Replicated customer ID exists. These Leads have a blank `Replicated_Customer_Id__c`, so a lookup by customer ID alone fails to find them.

## Root Cause

Salesforce's Lead conversion maps standard fields automatically (via org-level Lead Field Mapping in Setup), but custom fields require either declarative mapping configuration or explicit Apex code. In a system-to-system webhook handler running `without sharing`, declarative mapping is unreliable — the handler must own the field copy.

For the lookup issue: the Replicated customer lifecycle has two phases. `customer.pending_signup` fires before the customer record is created on the Replicated side, so there's no `customer_id` to store on the Lead. `customer.ep_user_joined` fires later, after the customer exists, and includes the `customer_id` and `joined_email`.

## Solution

### Post-Conversion Enrichment

After `Database.convertLead()`, iterate results in parallel with the original Lead list (same index) and update the converted Account:

```apex
private void enrichConvertedAccounts(
        List<Database.LeadConvertResult> results,
        List<Lead> leads,
        List<String> customerIds) {
    List<Account> toUpdate = new List<Account>();

    for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
            continue;
        }

        Lead lead = leads[i];
        Account acc = new Account(
            Id = results[i].getAccountId(),
            Replicated_Customer_Id__c = customerIds[i]
        );

        if (String.isNotBlank(lead.Replicated_License_Type__c)) {
            acc.Replicated_License_Type__c = lead.Replicated_License_Type__c;
        }
        if (String.isNotBlank(lead.Replicated_Channel__c)) {
            acc.Replicated_Channel__c = lead.Replicated_Channel__c;
        }
        if (lead.Replicated_License_Expiry__c != null) {
            acc.Replicated_License_Expiry__c = lead.Replicated_License_Expiry__c;
        }

        SyncGuard.inboundSyncIds.add(acc.Id);
        toUpdate.add(acc);
    }

    if (!toUpdate.isEmpty()) {
        update toUpdate;
    }
}
```

Index alignment works because `Database.convertLead()` returns results in submission order.

### Two-Tier Lead Lookup

Primary lookup by `Replicated_Customer_Id__c`, fallback by email:

```apex
// Tier 1: customer ID
Map<String, Lead> leadsByCustomerId = new Map<String, Lead>();
for (Lead l : [
    SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
           Replicated_Channel__c, Replicated_License_Expiry__c
    FROM Lead
    WHERE Replicated_Customer_Id__c IN :customerIds AND IsConverted = false
]) {
    leadsByCustomerId.put(l.Replicated_Customer_Id__c, l);
}

// Tier 2: email (for Leads without customer ID)
Map<String, Lead> leadsByEmail = new Map<String, Lead>();
if (!joinedEmails.isEmpty()) {
    for (Lead l : [
        SELECT Id, Email, Replicated_Customer_Id__c, Replicated_License_Type__c,
               Replicated_Channel__c, Replicated_License_Expiry__c
        FROM Lead
        WHERE Email IN :joinedEmails AND IsConverted = false
    ]) {
        leadsByEmail.put(l.Email, l);
    }
}

// Resolution: primary first, fallback second
Lead lead = leadsByCustomerId.get(customerId);
if (lead == null && String.isNotBlank(joinedEmail)) {
    lead = leadsByEmail.get(joinedEmail);
}
```

Both queries filter `IsConverted = false` to avoid matching already-converted Leads.

## Prevention

When implementing new handlers that convert Leads:

1. Always implement `enrichConvertedAccounts()` — never assume custom fields survive conversion.
2. Always test field preservation: assert each custom field value on the converted Account.
3. Consider whether the Lead was created by an earlier lifecycle handler that lacks the join key. If so, implement a fallback lookup by email or another stable identifier.
4. Maintain parallel lists (`conversions`, `conversionLeads`, `conversionCustomerIds`) at the same index to avoid mismatched enrichment.

## Related

- [Bidirectional Sync Loop Prevention](bidirectional-sync-loop-prevention.md) — SyncGuard pattern used after enrichment update
- [Trial Handler Bulkification](trial-handler-bulkification-governor-limit.md) — Bulk Lead creation patterns
- [Hardening CustomerUpdatedHandler](hardening-customer-updated-handler.md) — Partial-success DML and null guards
- GitHub: #86 (EpUserJoinedHandler), #75 (Enterprise Portal event handling)
