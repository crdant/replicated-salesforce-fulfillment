---
title: "feat: Revise webhook handler lifecycle — EP conversion, download tracking, order fulfillment"
type: feat
status: active
date: 2026-03-19
---

# Revise webhook handler lifecycle — EP conversion, download tracking, order fulfillment

## Overview

Decompose the current `AssetDownloadedHandler` monolith into distinct lifecycle handlers: Lead-to-ACO conversion moves to `customer.ep_user_joined`, asset downloads become activity records on a new `Replicated_Download__c` object, and paid downloads mark Order fulfillment. Also fix the two event type naming mismatches that silently drop events.

## Problem Statement / Motivation

The current `AssetDownloadedHandler` conflates three concerns — Lead conversion, Account creation, and download tracking — into a single event handler. This creates problems:

1. **Wrong conversion signal.** Download is too late — the customer has already connected to Enterprise Portal and pulled software before we convert the Lead. The first EP login (`customer.ep_user_joined`) is the real engagement signal.

2. **No download history.** Downloads are not recorded as Salesforce objects. The only side effect is Lead conversion, which is one-time. Subsequent downloads are invisible.

3. **No fulfillment tracking.** When a paid customer downloads software, there is no record that the Order has been fulfilled. The outbound flow creates the license, but the inbound flow never closes the loop.

4. **Silent event drops.** Two event types use display names instead of canonical API identifiers, so `TrialSignupHandler` and `AssetDownloadedHandler` never fire.

## Proposed Solution

**Deployment: all four phases deploy as a single `make deploy`.** Phase 1 activates event routing for `release.asset_downloaded` for the first time — if the old `AssetDownloadedHandler` (with Lead conversion logic) runs before Phases 3/4 replace it, stale conversion logic fires in production. Single deployment eliminates this risk.

### Phase 1: Fix event type naming mismatches

Correct the two display-name routing cases to canonical keys. This unblocks events that are already subscribed to and have working handlers.

**`ReplicatedWebhookSubscriber.trigger`:**

```apex
// BEFORE → AFTER
when 'Pending Self-Service Signup'  → when 'customer.pending_signup'
when 'Release Assets Downloaded'    → when 'release.asset_downloaded'
```

**Test fixtures** — update event type strings in:
- `TrialSignupHandlerTest.cls` — change `'Pending Self-Service Signup'` → `'customer.pending_signup'`
- `AssetDownloadedHandlerTest.cls` — change `'Release Assets Downloaded'` → `'release.asset_downloaded'`

**Documentation** — update display-name strings in code examples:
- `docs/solutions/integration-issues/trial-handler-bulkification-governor-limit.md` — lines 39, 73, 75

### Phase 2: New custom object and field

#### 2a. `Replicated_Download__c` custom object

New object following the `Replicated_Instance__c` pattern.

**Object definition** — `create-license/main/default/objects/Replicated_Download__c/Replicated_Download__c.object-meta.xml`:
- `deploymentStatus`: Deployed
- `sharingModel`: Read
- `nameField`: Auto-number (`DL-{0000}`)
- `label`: Replicated Download
- `pluralLabel`: Replicated Downloads

**Fields** — `create-license/main/default/objects/Replicated_Download__c/fields/`:

| Field API Name | Type | Required | External ID | Description |
|---|---|---|---|---|
| `Account__c` | Lookup(Account) | true | false | Parent Account (via `Replicated_Customer_Id__c` lookup) |
| `Asset_Type__c` | Text(50) | false | false | `helm_chart`, `embedded_cluster_bundle`, `proxy_image` |
| `Asset_Name__c` | Text(255) | false | false | Chart/bundle/image name |
| `Asset_Version__c` | Text(255) | false | false | Version tag |
| `Channel_Name__c` | Text(255) | false | false | Release channel name |
| `License_Type__c` | Text(50) | false | false | `paid`, `trial`, `dev`, `community` |
| `Downloaded_At__c` | DateTime | false | false | Timestamp from payload |
| `Replicated_Customer_Id__c` | Text(255) | false | false | Replicated customer ID for reconciliation |
| `App_Name__c` | Text(255) | false | false | Application name from payload |

No external ID / idempotency key — the `release.asset_downloaded` payload has no unique download identifier. Duplicate webhook deliveries create duplicate records; this is acceptable for an activity log (and consistent with `LicenseExpiringHandler` creating duplicate Tasks on replay).

**Lookup field details** for `Account__c`:
- `deleteConstraint`: Restrict
- `relationshipLabel`: Replicated Downloads
- `relationshipName`: Replicated_Downloads

#### 2b. `Order.FulfilledAt__c` field

**Field definition** — `create-license/main/default/objects/Order/fields/FulfilledAt__c.field-meta.xml`:
- Type: DateTime
- Required: false
- External ID: false
- Description: Timestamp when the customer first downloaded paid software, confirming order fulfillment
- `trackHistory`: false (matches existing Order fields)

**FLS**: Add `fieldPermissions` entries for all profiles that have FLS on `Order.LicenseId__c` (use that field's profile entries as the template).

**`package.xml`**: Add `Order.FulfilledAt__c` to `CustomField` members, add `Replicated_Download__c` to `CustomObject` members, add all `Replicated_Download__c.{field}` entries to `CustomField` members.

### Phase 3: New `EpUserJoinedHandler` for Lead-to-ACO conversion

New handler triggered by `customer.ep_user_joined` when `is_first_user == true`. This replaces the conversion logic currently in `AssetDownloadedHandler`.

**New file**: `create-license/main/default/classes/EpUserJoinedHandler.cls` + `.cls-meta.xml`

**Handler logic:**

```
execute(QueueableContext):
  1. Parse payloads, collect customer IDs
  2. Filter: skip events where is_first_user != true
  3. Idempotency: bulk query Accounts by Replicated_Customer_Id__c, skip if Account exists
  4. Bulk query unconverted Leads by Replicated_Customer_Id__c
     - Fallback: if no Lead found by customer_id, try joined_email
  5. For Leads found: Database.convertLead(), then enrichConvertedAccounts()
     - Copy Replicated_Customer_Id__c, Replicated_License_Type__c,
       Replicated_Channel__c, Replicated_License_Expiry__c from Lead to Account
  6. For no Lead found: create Account + Contact + Opportunity directly
     - Account.Name = customer_name, Account.Replicated_Customer_Id__c = customer_id
     - Contact.Email = joined_email, Contact.LastName = customer_name
     - Opportunity.StageName = 'Qualification', CloseDate = today + 30
     - Use Database.setSavepoint() / rollback() for atomicity
  7. SyncGuard.inboundSyncIds.add() for all Lead, Account, Contact, Opportunity IDs
```

The Lead field enrichment (step 5) is critical — Salesforce Lead conversion does NOT automatically map custom fields. The current `AssetDownloadedHandler.enrichConvertedAccounts()` (lines 109-147) is the template.

**Trigger routing** — add to `ReplicatedWebhookSubscriber.trigger`:

```apex
List<Replicated_Webhook__e> epUserJoinedEvents = new List<Replicated_Webhook__e>();

// In switch:
when 'customer.ep_user_joined' {
    epUserJoinedEvents.add(event);
}

// After loop:
if (!epUserJoinedEvents.isEmpty()) {
    System.enqueueJob(new EpUserJoinedHandler(epUserJoinedEvents));
}
```

**Webhook subscription** — add `customer.ep_user_joined` to `hack/setup-webhook-subscription` event configs.

**New test class**: `create-license/main/default/classes/EpUserJoinedHandlerTest.cls` + `.cls-meta.xml`

Test cases:
- `testFirstUserConvertsLead` — Lead exists with Replicated fields, converts to ACO, fields carry over
- `testFirstUserNoLeadCreatesAco` — no Lead, creates Account + Contact + Opportunity directly
- `testFirstUserAccountAlreadyExists` — idempotent skip
- `testNotFirstUserSkipped` — `is_first_user == false`, no DML
- `testLeadLookupFallsBackToEmail` — Lead has no `Replicated_Customer_Id__c`, matched by `joined_email`
- `testMalformedPayload` — invalid JSON, graceful skip
- `testBulkEvents` — 200 events within governor limits

### Phase 4: Rewrite `AssetDownloadedHandler`

Edit the existing `AssetDownloadedHandler.cls` in place (same class name, same trigger routing). Strip all Lead conversion and ACO creation logic. Replace the body with download tracking and conditional order fulfillment. The test class `AssetDownloadedHandlerTest.cls` is also edited in place with entirely new test methods.

**Rewritten handler logic:**

```
execute(QueueableContext):
  1. Parse payloads, collect customer IDs
  2. Bulk query Accounts by Replicated_Customer_Id__c
  3. For each event:
     a. Look up Account — if none found, log warning and skip
     b. Build Replicated_Download__c record (Account lookup, asset fields, timestamp)
  4. Bulk insert Replicated_Download__c records
     (No SyncGuard needed — no outbound triggers exist on Replicated_Download__c)
  5. For events where license_type == 'paid':
     a. Collect Account IDs
     b. Bulk query Orders: Account's Replicated_Customer_Id__c matches,
        LicenseId__c != null, FulfilledAt__c = null
        Join through OpportunityLineItem.Product2.Application__c = payload app_id
        ORDER BY CreatedDate ASC LIMIT 1 per Account
     c. Set FulfilledAt__c = downloaded_at from payload
     d. Bulk update Orders
     e. SyncGuard.inboundSyncIds.add() for updated Order IDs
```

**Order matching strategy**: Match on Account + `LicenseId__c != null` + `FulfilledAt__c = null` + `Product2.Application__c = payload app_id`. If multiple still match, take the oldest (`ORDER BY CreatedDate ASC`). This prevents a download for one app from fulfilling a different app's Order.

**Download-before-Account race condition**: EP login is required before download, so Account should always exist. If it doesn't (webhook delivery reordering), log a warning and skip. No recovery path — the download is lost. This is the correct tradeoff: adding a retry queue or pending-downloads buffer for a near-impossible race adds complexity with no practical benefit.

**Download tracking and order fulfillment are independent operations**: If download insert succeeds but Order update fails (or vice versa), each proceeds independently. No savepoint wrapper — these are not an atomic unit.

**Updated test class**: `AssetDownloadedHandlerTest.cls` — full rewrite

Test cases:
- `testTrialDownloadCreatesRecord` — `license_type = 'trial'`, download record created, no Order update
- `testPaidDownloadFulfillsOrder` — `license_type = 'paid'`, download record created AND Order `FulfilledAt__c` set
- `testPaidDownloadOrderAlreadyFulfilled` — `FulfilledAt__c` already set, no update
- `testPaidDownloadNoOrder` — paid download but no matching Order, download record still created
- `testNoAccountSkips` — unknown `customer_id`, no DML
- `testMalformedPayload` — invalid JSON, graceful skip
- `testBulkDownloads` — 200 events within governor limits
- `testMultipleOrdersMatchesCorrectApp` — two unfulfilled Orders for different apps, correct one fulfilled

## Technical Considerations

- **Phase 1 enables previously-dead handlers.** After fixing the naming mismatches, `TrialSignupHandler` and the rewritten `AssetDownloadedHandler` will process events for the first time. Platform Event 24-hour retention limits the blast radius. This is why all phases deploy together — see deployment note at top of Proposed Solution.

- **Governor limits.** Adding a sixth `System.enqueueJob()` call in the trigger is fine — the limit is 50 per transaction, and the trigger currently uses at most 5.

- **`is_first_customer_pull` is not used.** Confirmed via vandoor PR #9206 that this flag is write-once per customer lifetime — it does not reset when license type changes from trial to paid. The `license_type` field combined with Order state (`FulfilledAt__c = null`) is the correct fulfillment signal.

- **No backfill needed.** Existing Orders with `LicenseId__c` that were already "fulfilled" before this feature simply won't have `FulfilledAt__c` set. New tracking starts from deployment forward. Reports can treat `FulfilledAt__c = null` as "pre-feature" rather than "unfulfilled."

- **FLS for new fields.** Per `docs/solutions/build-errors/salesforce-fls-required-field-deployment-rejection.md`: required fields cannot have FLS entries. `Account__c` on `Replicated_Download__c` is required, so no FLS entry for that field. All other fields are optional and need FLS entries across all profiles.

## System-Wide Impact

- **Interaction graph**: `Replicated_Webhook__e` → `ReplicatedWebhookSubscriber` trigger → `EpUserJoinedHandler` (Lead conversion) or `AssetDownloadedHandler` (download + fulfillment). EP handler creates Account/Contact/Opportunity (fires `CloseWonOpportunity` trigger if Opportunity created — but that trigger only fires on Opportunity update with `StageName = 'Closed Won'`, so no cascade). Asset handler updates Order `FulfilledAt__c` (fires `FulfillOrder` trigger — but that trigger only fires when `Status == 'Activated'`, so the `FulfilledAt__c` update does NOT trigger re-fulfillment).
- **Error propagation**: Malformed payloads caught and skipped per handler. No Account found = skip with warning. DML failures logged but do not propagate across handlers (each is a separate Queueable).
- **State lifecycle risks**: The EP handler's direct-create path uses savepoint/rollback. The Order update is idempotent (`FulfilledAt__c = null` guard). Download inserts are append-only.
- **API surface parity**: No new outbound API calls. The inbound webhook receiver is unchanged.

## Acceptance Criteria

### Phase 1
- [ ] Trigger routes `'customer.pending_signup'` (not display name) to `TrialSignupHandler`
- [ ] Trigger routes `'release.asset_downloaded'` (not display name) to `AssetDownloadedHandler`
- [ ] All test fixtures use canonical event type keys
- [ ] Documentation examples updated

### Phase 2
- [ ] `Replicated_Download__c` custom object deployed with all fields
- [ ] `Order.FulfilledAt__c` field deployed
- [ ] FLS configured for all profiles
- [ ] `package.xml` updated with new object, fields
- [ ] `make deploy` succeeds

### Phase 3
- [x] `EpUserJoinedHandler` converts Lead to ACO on `is_first_user == true`
- [x] Handler enriches Account with all Replicated custom fields from Lead
- [x] Handler creates ACO directly when no Lead exists
- [x] Handler skips when `is_first_user == false`
- [x] Handler is idempotent (Account already exists = skip)
- [x] Lead lookup falls back to email when `Replicated_Customer_Id__c` not set
- [x] SyncGuard applied for all created/updated records
- [x] Trigger routes `'customer.ep_user_joined'` to handler
- [x] Webhook subscription includes `customer.ep_user_joined`
- [x] All tests pass

### Phase 4
- [x] `AssetDownloadedHandler` creates `Replicated_Download__c` on every download
- [x] Handler sets `FulfilledAt__c` on unfulfilled Order when `license_type == 'paid'`
- [x] Order matching uses `app_id` to select correct Order
- [x] Handler skips gracefully when no Account found
- [x] No Lead conversion or ACO creation logic remains
- [x] SyncGuard applied for Order updates
- [x] All tests pass
- [x] All existing tests continue to pass

## Dependencies & Risks

- **`customer.ep_user_joined` event delivery.** Requires Replicated platform to actually send this event. The event type is documented in vandoor source and the plan document confirms the payload schema.
- **Subscription recreation window.** When recreating the webhook subscription to add `customer.ep_user_joined`, there is a brief window where no subscription exists. Events during this window are lost. Mitigate by running during low-traffic periods.
- **Atomic deployment.** All four phases ship in a single `make deploy`. Phase 1 activates routing for `release.asset_downloaded`; if the old handler runs before Phases 3/4 replace it, stale Lead conversion logic fires.

## Open Questions

1. **Should `ep_user_joined` with `is_first_user == false` create a Task or other activity?** Current plan: skip entirely. Could follow `LicenseExpiringHandler` pattern and create a Task on the Account owner ("User X joined Enterprise Portal for Customer Y"). Decide before implementation.

2. **Should `ep_invite_sent` and `ep_access_granted` also be subscribed and handled?** The existing plan proposed Task creation for these. This plan focuses on the delta only, but these could be added as a follow-on. Decide scope.

## Sources & References

- Research document: `docs/research/2026-03-19-replicated-webhook-notification-inventory.md`
- Previous plan (partially superseded): `docs/plans/2026-03-19-001-feat-ep-events-and-event-type-fixes-plan.md`
- Canonical event types: `docs/solutions/integration-issues/webhook-event-type-naming-mismatch.md`
- Bulkification patterns: `docs/solutions/integration-issues/trial-handler-bulkification-governor-limit.md`
- SyncGuard patterns: `docs/solutions/integration-issues/bidirectional-sync-loop-prevention.md`
- FLS deployment rules: `docs/solutions/build-errors/salesforce-fls-required-field-deployment-rejection.md`
- Data model patterns: `docs/solutions/integration-issues/salesforce-data-model-review-hardening.md`
- Vandoor PR #9206: `is_first_customer_pull` write-once semantics, `release.asset_downloaded` payload schema
- EP event payloads: `replicatedhq/vandoor` `pkg/notifications/events/customer_ep_user_joined.go`
