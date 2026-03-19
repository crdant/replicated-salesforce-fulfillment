---
title: "Hardens customer.updated handler with review-driven fixes"
category: "integration-issues"
date: "2026-03-19"
tags:
  - "webhook-handlers"
  - "apex-patterns"
  - "logging-policy"
  - "dml-patterns"
  - "null-safety"
  - "code-duplication"
  - "code-review"
severity: "medium"
component: "Replicated webhook event processing pipeline"
related_issues:
  - "#89"
  - "#76"
---

# Hardening CustomerUpdatedHandler

## Problem

Code review of PR #89 (`CustomerUpdatedHandler` for `customer.updated` webhooks) revealed five hardening issues across security, reliability, data integrity, and maintainability. All were in the handler itself or in shared patterns across the handler pipeline.

## Root Cause

Five distinct issues, each with a different origin:

1. **Payload values in debug logs** — `customer_id` and `dateString` logged in `System.debug()`, violating the trigger's own comment: "Avoid logging payload or customer data — debug logs are visible to admins." Likely copied from debugging during development without sanitizing before commit.

2. **All-or-nothing DML** — Bare `update toUpdate` used instead of `Database.update(toUpdate, false)`. `CustomerCreatedHandler` already used partial success, but the pattern wasn't enforced on new handlers.

3. **Missing null guards on boolean-flagged fields** — `channel_name` and `expires_at` were written when their respective change flags were true, without null-checking the values. The `customer_name` and `license_type` paths already had null guards — an inconsistency within the same method.

4. **SOQL selecting unused fields** — Query selected `Name`, `Replicated_License_Type__c`, `Replicated_Channel__c`, and `Replicated_License_Expiry__c`, but the handler only reads `Id` and `Replicated_Customer_Id__c`. Change detection uses payload fields, not DB comparison.

5. **Duplicated parseDate** — Identical private `parseDate()` method in three handlers (`CustomerUpdatedHandler`, `CustomerCreatedHandler`, `LicenseExpiringHandler`).

## Solution

### 1. Strip Payload Values from Debug Logs

```apex
// Before:
System.debug(LoggingLevel.WARN,
    'CustomerUpdatedHandler: no Account for customer_id ' + customerId);
System.debug(LoggingLevel.WARN,
    'CustomerUpdatedHandler: failed to parse date: ' + dateString);

// After:
System.debug(LoggingLevel.WARN,
    'CustomerUpdatedHandler: no matching Account found, skipping event');
System.debug(LoggingLevel.WARN,
    'WebhookPayloadUtils: failed to parse date');
```

### 2. Switch to Partial-Success DML

```apex
// Before:
if (!toUpdate.isEmpty()) {
    update toUpdate;
}

// After:
if (!toUpdate.isEmpty()) {
    List<Database.SaveResult> results = Database.update(toUpdate, false);
    for (Database.SaveResult result : results) {
        if (!result.isSuccess()) {
            System.debug(LoggingLevel.WARN,
                'CustomerUpdatedHandler: partial update failure, skipping record');
        }
    }
}
```

### 3. Add Null Guards on Boolean-Flagged Fields

```apex
// Before (channel):
Boolean channelChanged = (Boolean) data.get('channel_changed');
if (channelChanged == true) {
    acc.Replicated_Channel__c = (String) data.get('channel_name');
    changed = true;
}

// After:
Boolean channelChanged = (Boolean) data.get('channel_changed');
String channelName = (String) data.get('channel_name');
if (channelChanged == true && channelName != null) {
    acc.Replicated_Channel__c = channelName;
    changed = true;
}

// Before (expiry):
if (expirationChanged == true) {
    acc.Replicated_License_Expiry__c = parseDate((String) data.get('expires_at'));
    changed = true;
}

// After:
if (expirationChanged == true) {
    Date expiryDate = WebhookPayloadUtils.parseDate((String) data.get('expires_at'));
    if (expiryDate != null) {
        acc.Replicated_License_Expiry__c = expiryDate;
        changed = true;
    }
}
```

### 4. Trim SOQL to Used Fields

```apex
// Before:
SELECT Id, Name, Replicated_Customer_Id__c, Replicated_License_Type__c,
       Replicated_Channel__c, Replicated_License_Expiry__c
FROM Account WHERE Replicated_Customer_Id__c IN :customerIds

// After:
SELECT Id, Replicated_Customer_Id__c
FROM Account WHERE Replicated_Customer_Id__c IN :customerIds
```

### 5. Extract Shared parseDate Utility

New class `WebhookPayloadUtils.cls`:

```apex
public class WebhookPayloadUtils {
    public static Date parseDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            if (dateString.contains('T')) {
                dateString = dateString.substringBefore('T');
            }
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WebhookPayloadUtils: failed to parse date');
            return null;
        }
    }
}
```

Replaced private `parseDate()` in `CustomerUpdatedHandler`, `CustomerCreatedHandler`, and `LicenseExpiringHandler` with `WebhookPayloadUtils.parseDate()`.

## Verification

All 54 org tests pass (0 failures) after all five fixes applied, including existing tests for `CustomerCreatedHandler` and `LicenseExpiringHandler` that now call the shared utility.

## Prevention Strategies

### Code Review Checklist for Webhook Handlers

**Security & Compliance:**
- [ ] No customer IDs, email addresses, or payload field values in `System.debug()` calls
- [ ] Operational messages only: "skipped event", "record not found", "update failed"

**Data Integrity:**
- [ ] Every field write guarded by both a change flag AND a null check
- [ ] Boolean change flags are intent signals, not value guarantees

**Reliability:**
- [ ] DML uses `Database.update(list, false)` or `Database.insert(list, dmlOpts)` for partial success
- [ ] Failed records logged at WARN level without payload values

**Clarity & Maintainability:**
- [ ] SOQL SELECT only includes fields actually read in handler logic
- [ ] No duplicated utility methods — use `WebhookPayloadUtils` for shared operations
- [ ] Rule of three: third copy of a utility method triggers extraction

### Key Principle

Boolean change flags mean "something changed" — they do NOT guarantee the new value is present. Always null-check the value independently of the flag.

## Related Documentation

- [Missing customer.updated Webhook Handler](missing-customer-updated-webhook-handler.md) — Original handler implementation
- [Bidirectional Sync Loop Prevention with SyncGuard](bidirectional-sync-loop-prevention.md) — SyncGuard pattern applied in all handlers
- [Webhook Receiver Security & Reliability Hardening](../security-issues/webhook-receiver-code-review-findings.md) — Upstream receiver security review
- [Event Type Constants Extraction](event-type-constants-extraction.md) — Event type string centralization pattern
- [Trial Lifecycle Handler Bulkification](trial-handler-bulkification-governor-limit.md) — Bulk processing patterns for Queueable handlers

## Related GitHub Issues

| Issue | Title | Relationship |
|-------|-------|-------------|
| [#89](https://github.com/crdant/replicated-salesforce-fulfillment/pull/89) | Adds customer.updated webhook handler | PR where findings were identified and fixed |
| [#76](https://github.com/crdant/replicated-salesforce-fulfillment/issues/76) | Add customer.updated handler | Parent issue |
| [#72](https://github.com/crdant/replicated-salesforce-fulfillment/issues/72) | Handle Enterprise Portal webhook events | Epic |
| [#6](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6) | Event-driven bidirectional sync | Epic covering all webhook event handling |
