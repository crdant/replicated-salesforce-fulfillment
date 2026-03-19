---
title: "Adds customer.updated event handler for Replicated webhook pipeline"
category: "integration-issues"
date: "2026-03-19"
tags:
  - "replicated-platform"
  - "webhook-events"
  - "bidirectional-sync"
  - "apex-handlers"
  - "account-reconciliation"
severity: "medium"
component: "Replicated webhook event processing pipeline"
related_issues:
  - "#76"
  - "#72"
  - "#6"
---

# Missing customer.updated Webhook Handler

## Problem

The Replicated webhook subscription was configured to receive `customer.updated` events, but the Salesforce `ReplicatedWebhookSubscriber` trigger had no routing case for that event type. All incoming `customer.updated` webhooks were silently discarded in the `when else` branch with only a debug log, preventing any customer profile synchronization from Replicated back to Salesforce.

## Root Cause

The trigger's switch statement did not include a `'customer.updated'` case, and no handler class existed to process these events. The subscription was created (Phase 3 of #72) but the corresponding code was not implemented — a gap between subscription configuration and trigger routing.

## Solution

Four files changed or created to establish complete event routing and handling:

### 1. ReplicatedEventType.cls — Event Type Constant

```apex
public static final String CUSTOMER_UPDATED = 'customer.updated';
```

### 2. ReplicatedWebhookSubscriber.trigger — Event Routing

```apex
List<Replicated_Webhook__e> customerUpdatedEvents = new List<Replicated_Webhook__e>();

// In switch:
when 'customer.updated' {
    customerUpdatedEvents.add(event);
}

// After switch:
if (!customerUpdatedEvents.isEmpty()) {
    System.enqueueJob(new CustomerUpdatedHandler(customerUpdatedEvents));
}
```

### 3. CustomerUpdatedHandler.cls — Queueable Handler

A `without sharing` Queueable class that:

- **Parses payloads** and collects customer IDs for bulk Account lookup via `Replicated_Customer_Id__c`
- **Conditionally syncs 4 fields** using change-tracking indicators from the webhook payload:
  - `customer_name` → `Account.Name` (only when `old_customer_name` differs)
  - `license_type` → `Account.Replicated_License_Type__c` (only when `old_license_type` differs)
  - `channel_name` → `Account.Replicated_Channel__c` (only when `channel_changed == true`)
  - `expires_at` → `Account.Replicated_License_Expiry__c` (only when `expiration_changed == true`)
- **Applies SyncGuard** — adds Account ID to `SyncGuard.inboundSyncIds` before DML to prevent bidirectional sync loops
- **No-op optimization** — skips DML entirely when no fields changed

### 4. CustomerUpdatedHandlerTest.cls — 8 Test Methods

| Test | Scenario |
|------|----------|
| `testSyncsCustomerName` | Name updates when `old_customer_name` differs |
| `testSyncsLicenseType` | License type updates when `old_license_type` differs |
| `testSyncsChannel` | Channel updates when `channel_changed == true` |
| `testSyncsExpiry` | Expiry updates when `expiration_changed == true` |
| `testNoChangeNoOp` | No DML when all change flags are false; SyncGuard not populated |
| `testNoMatchingAccount` | Gracefully skips when no Account matches customer ID |
| `testSyncGuardApplied` | Verifies `SyncGuard.inboundSyncIds` contains Account ID after update |
| `testBulkEvents` | Multiple events for different accounts processed in one batch |
| `testMalformedPayloadSkipped` | Invalid JSON handled without exception |

## Verification

All 56 org tests pass (100% pass rate) including the 8 new `CustomerUpdatedHandlerTest` methods. Deployed successfully to the Salesforce org.

## Prevention Strategies

### Treat Subscriptions and Handlers as Atomic

Any changes to webhook subscriptions (via `hack/setup-webhook-subscription` or direct API) must include corresponding code changes — routing case + handler class. A subscription without a handler is incomplete work.

### Make Silent Drops Visible

The trigger's `when else` branch only logs at DEBUG level. Consider logging unhandled event types at ERROR level or publishing an error record so gaps become obvious during testing and production monitoring.

### Checklist for Adding New Event Handlers

When adding support for a new webhook event type:

- [ ] Add event type constant to `ReplicatedEventType.cls`
- [ ] Add routing case to `ReplicatedWebhookSubscriber` trigger switch statement
- [ ] Add event collection list and enqueue block in trigger
- [ ] Create handler class implementing `Queueable`
- [ ] Apply `SyncGuard.inboundSyncIds` before any DML that could trigger outbound sync
- [ ] Create test class covering: happy path, no-op, no matching record, SyncGuard, bulk, malformed payload
- [ ] Verify event type string matches canonical key from Replicated API (see [webhook-event-type-naming-mismatch.md](webhook-event-type-naming-mismatch.md))
- [ ] Deploy and run full test suite

## Related Documentation

- [Bidirectional Sync Loop Prevention with SyncGuard](bidirectional-sync-loop-prevention.md) — SyncGuard pattern applied in this handler
- [Webhook Receiver with HMAC Signature Verification](webhook-receiver-hmac-verification.md) — Platform Event publishing architecture
- [Webhook Event Type Naming Mismatch](webhook-event-type-naming-mismatch.md) — Canonical event type reference table
- [Salesforce Webhook Endpoint Testing](salesforce-webhook-endpoint-testing-integration.md) — Endpoint verification steps

## Related GitHub Issues

| Issue | Title | Relationship |
|-------|-------|-------------|
| [#76](https://github.com/crdant/replicated-salesforce-fulfillment/issues/76) | Add `customer.updated` handler | This issue |
| [#72](https://github.com/crdant/replicated-salesforce-fulfillment/issues/72) | Handle Enterprise Portal webhook events | Parent — Phase 3 |
| [#6](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6) | Event-driven bidirectional sync | Epic covering all webhook event handling |
