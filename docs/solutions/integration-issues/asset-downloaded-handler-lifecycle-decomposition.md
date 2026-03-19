---
title: "Rewrite AssetDownloadedHandler for download tracking and order fulfillment"
category: integration-issues
date: 2026-03-19
tags:
  - webhook-handler
  - download-tracking
  - order-fulfillment
  - handler-decomposition
  - separation-of-concerns
related_issues:
  - "#85 — Rewrite AssetDownloadedHandler"
  - "#86 — EpUserJoinedHandler (parallel, takes Lead conversion)"
  - "#88 — Replicated_Download__c object and Order.FulfilledAt__c field"
  - "#84 — Schema spec for new objects and fields"
components:
  - AssetDownloadedHandler.cls
  - AssetDownloadedHandlerTest.cls
  - Replicated_Download__c
  - Order.FulfilledAt__c
severity: major
---

# Rewrite AssetDownloadedHandler for download tracking and order fulfillment

## Problem

The original `AssetDownloadedHandler` conflated three concerns into one `release.asset_downloaded` webhook handler: Lead conversion, Account/Contact/Opportunity creation, and download processing. This caused three issues:

1. **No download history** — downloads were never persisted as Salesforce objects. The only side effect was Lead conversion, which is one-time. Subsequent downloads were invisible.
2. **No fulfillment tracking** — when a paid customer downloaded software, there was no record that the Order had been fulfilled. The outbound flow created the license, but the inbound flow never closed the loop.
3. **Wrong conversion signal** — download arrives too late in the customer journey. The first EP login (`customer.ep_user_joined`) is the real engagement signal.

## Root Cause

The handler was designed before the `Replicated_Download__c` object and `Order.FulfilledAt__c` field existed, and before the `customer.ep_user_joined` webhook event was available. All lifecycle logic was crammed into the only inbound event available at the time.

## Solution

Rewrote `AssetDownloadedHandler` with two independent operations, stripping all Lead/ACO logic (moved to `EpUserJoinedHandler` in #86).

### Operation 1: Download Tracking (all events)

For every `release.asset_downloaded` event, create a `Replicated_Download__c` record:

1. Parse payloads, collect customer IDs
2. Bulk query Accounts by `Replicated_Customer_Id__c`
3. Build `Replicated_Download__c` records (Account lookup, asset type/name/version, channel, license type, timestamp, app name)
4. Bulk insert — no SyncGuard needed (no outbound triggers on `Replicated_Download__c`)
5. Skip with warning log if no Account found for `customer_id`

### Operation 2: Order Fulfillment (paid downloads only)

For events where `license_type == 'paid'`, find and fulfill the matching Order:

1. Collect AccountIds and appIds from paid events
2. Query unfulfilled Orders:

```apex
SELECT Id, AccountId, CreatedDate, OpportunityId
FROM Order
WHERE AccountId IN :paidAccountIds
  AND LicenseId__c != null
  AND FulfilledAt__c = null
ORDER BY CreatedDate ASC
```

3. Resolve which app each Order belongs to via OpportunityLineItem:

```apex
SELECT OpportunityId, Product2.Application__c
FROM OpportunityLineItem
WHERE OpportunityId IN :oppIds
  AND Product2.Application__c IN :paidAppIds
  AND Product2.IsAddOn__c = false
```

4. Build composite key map `AccountId:appId` to oldest unfulfilled Order
5. Set `FulfilledAt__c` to `downloaded_at` timestamp
6. `SyncGuard.inboundSyncIds.add()` for updated Order IDs
7. Bulk update Orders

### Key Pattern: Two-Query Join for Order-to-App Matching

Salesforce has no direct Order-to-Product relationship. The join path is Order -> Opportunity -> OpportunityLineItem -> Product2.Application__c. This requires two SOQL queries:

```apex
// Build composite key: AccountId:appId → oldest unfulfilled Order
Map<String, Order> ordersByKey = new Map<String, Order>();
for (Order o : unfulfilled) {
    String appId = oppToAppId.get(o.OpportunityId);
    if (appId == null) { continue; }
    String key = o.AccountId + ':' + appId;
    if (!ordersByKey.containsKey(key)) {
        ordersByKey.put(key, o); // First = oldest (query ordered ASC)
    }
}
```

### DateTime Parsing

ISO-8601 timestamps from webhooks parsed via JSON deserialization:

```apex
private static DateTime parseDateTime(String dateTimeStr) {
    if (String.isBlank(dateTimeStr)) { return DateTime.now(); }
    try {
        return (DateTime) JSON.deserialize('"' + dateTimeStr + '"', DateTime.class);
    } catch (Exception e) {
        return DateTime.now();
    }
}
```

The existing `WebhookPayloadUtils.parseDate()` only returns `Date` (strips time). The JSON deserialization trick handles ISO-8601 with timezone correctly.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| No SyncGuard on download inserts | `Replicated_Download__c` has no outbound triggers — no sync loop risk |
| SyncGuard on Order updates | `FulfillOrder` trigger fires on Order update; must prevent re-sync |
| No savepoint wrapper | Download tracking and order fulfillment are independent operations serving different business purposes |
| Oldest Order per composite key | If multiple unfulfilled Orders exist for same Account:app, fulfill the first created |
| `DateTime.now()` fallback | `Downloaded_At__c` is required; fallback prevents DML failure on malformed timestamps |

## Test Coverage

8 test methods covering the full matrix:

| Test | Scenario |
|------|----------|
| `testTrialDownloadCreatesRecord` | Trial download creates `Replicated_Download__c`, no Order update |
| `testPaidDownloadFulfillsOrder` | Paid download creates record AND sets `FulfilledAt__c` |
| `testPaidDownloadOrderAlreadyFulfilled` | `FulfilledAt__c` already set, no update |
| `testPaidDownloadNoOrder` | Paid download with no matching Order, download still created |
| `testNoAccountSkips` | Unknown `customer_id`, no DML |
| `testMalformedPayload` | Invalid JSON, no exception |
| `testBulkDownloads` | 200 events within governor limits |
| `testMultipleOrdersMatchesCorrectApp` | Two Orders for different apps, correct one fulfilled |

Test data setup requires the full Order chain: Product2 -> PricebookEntry -> Opportunity -> OpportunityLineItem -> Order. Use `Test.getStandardPricebookId()` for the standard pricebook.

## Prevention & Best Practices

### Handler Decomposition

When a webhook handler grows to serve multiple business processes, decompose it. Each handler should map to one clear business outcome. The trigger router already supports multiple handlers per event type via separate collection lists and `System.enqueueJob()` calls.

### SyncGuard Discipline

Apply SyncGuard only to records that have outbound triggers. Check the trigger chain before adding guards:

- Record has `AFTER INSERT/UPDATE` trigger that makes outbound API calls -> SyncGuard required
- Record has no outbound trigger -> SyncGuard not needed

### Order-to-Product Join Pattern

Always use the two-query approach when matching Orders to Replicated app_ids. There is no shortcut through the Salesforce data model. Document the join path in code comments near the query.

### Independent vs. Dependent Operations

Use savepoint wrappers only when failure of one operation invalidates the other (e.g., Account + Contact + Opportunity creation). When operations serve different business purposes and can partially succeed, keep them independent.

## Related Documentation

- `docs/solutions/integration-issues/bidirectional-sync-loop-prevention.md` — SyncGuard pattern
- `docs/solutions/integration-issues/trial-handler-bulkification-governor-limit.md` — Bulk handler patterns
- `docs/solutions/integration-issues/missing-customer-updated-webhook-handler.md` — Reference handler implementation
- `docs/solutions/integration-issues/hardening-customer-updated-handler.md` — Handler hardening checklist
- `docs/solutions/integration-issues/webhook-event-type-naming-mismatch.md` — Event type naming
- `docs/solutions/integration-issues/event-type-constants-extraction.md` — ReplicatedEventType constants
- `docs/solutions/build-errors/salesforce-fls-required-field-deployment-rejection.md` — FLS rules for required fields
- `docs/solutions/integration-issues/salesforce-dx-metadata-review-findings.md` — Replicated_Download__c schema review
- `docs/plans/2026-03-19-002-feat-revise-webhook-handler-lifecycle-plan.md` — Full lifecycle plan (Phase 4)
- `docs/research/2026-03-19-replicated-webhook-notification-inventory.md` — Webhook event inventory
