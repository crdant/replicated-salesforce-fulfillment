---
title: "feat: Handle Enterprise Portal webhook events and fix event type naming mismatches"
type: feat
status: active
date: 2026-03-19
---

# Handle Enterprise Portal webhook events and fix event type naming mismatches

## Overview

The integration subscribes to and handles 8 Replicated webhook event types, but three Enterprise Portal events (`customer.ep_invite_sent`, `customer.ep_access_granted`, `customer.ep_user_joined`) are completely unhandled, and two trigger routing cases use display names instead of canonical API keys — meaning those events are silently dropped when Replicated sends the canonical key in the webhook payload.

## Problem Statement / Motivation

**Enterprise Portal events**: The project enables Enterprise Portal and trial signup via `hack/setup-enterprise-portal`, but never subscribes to or handles the three EP webhook events. When a vendor invites a customer to EP, when the customer gains access, or when a user joins — Salesforce has no visibility into these lifecycle events. This is a gap in the bidirectional sync story.

**Naming mismatches**: Two trigger cases route on display-name strings instead of canonical event type keys:
- `'Pending Self-Service Signup'` → canonical key is `'customer.pending_signup'`
- `'Release Assets Downloaded'` → canonical key is `'release.asset_downloaded'`

The subscription script sends the correct canonical keys. The `ReplicatedWebhookReceiver` copies the raw `event` field from the payload into `Event_Type__c`. If Replicated sends canonical keys (which it does — confirmed by the `Key()` method contract documented in `docs/solutions/integration-issues/webhook-event-type-naming-mismatch.md`), these events hit the `when else` branch and are silently discarded.

**`is_first_customer_pull`**: This field DOES exist in the `release.asset_downloaded` webhook payload (confirmed via `AssetDownloadedEvent` struct in `replicatedhq/vandoor` `pkg/notifications/events/asset_downloaded.go`). It is a boolean that is `true` when the pull is the first completed software pull for the customer across all asset types. The current `AssetDownloadedHandler` ignores this field — it only reads `customer_id`, `customer_name`, and `email` from the payload. The handler's Account-exists idempotency check provides a coarser version of "first pull" semantics (skip if Account already exists), but `is_first_customer_pull` is the authoritative signal from the platform. The handler should be updated to use this field to conditionally trigger Lead conversion / Account creation only on first pull, rather than relying solely on the Account-exists check.

**`customer.updated` dead subscription**: The subscription script subscribes to `customer.updated` but the trigger has no corresponding `when` case. Every `customer.updated` event is published as a Platform Event, reaches the trigger, and gets silently dropped. This needs a routing decision (handle it or unsubscribe).

## Proposed Solution

### Phase 1: Fix event type naming mismatches in trigger, tests, and docs

Correct the two display-name routing cases to use canonical keys. This unblocks events that are already subscribed to and have working handlers.

**`create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger`:**

```apex
// Line 23: BEFORE
when 'Pending Self-Service Signup' {
// AFTER
when 'customer.pending_signup' {

// Line 29: BEFORE
when 'Release Assets Downloaded' {
// AFTER
when 'release.asset_downloaded' {
```

**Test fixtures** — update event type strings in:
- `create-license/main/default/classes/TrialSignupHandlerTest.cls` — change `'Pending Self-Service Signup'` → `'customer.pending_signup'` in all test payloads and Platform Event construction
- `create-license/main/default/classes/AssetDownloadedHandlerTest.cls` — change `'Release Assets Downloaded'` → `'release.asset_downloaded'` in all test payloads and Platform Event construction

**Documentation** — update display-name strings in code examples:
- `docs/solutions/integration-issues/trial-handler-bulkification-governor-limit.md` — code examples on lines 39, 73, 75 use old display names; update to canonical keys to prevent future copy-paste errors

### Phase 1b: Use `is_first_customer_pull` in `AssetDownloadedHandler`

The handler currently reads only `customer_id`, `customer_name`, and `email` from the payload. The `release.asset_downloaded` payload includes `is_first_customer_pull` (boolean) — `true` when this is the customer's first software pull across all asset types.

**`create-license/main/default/classes/AssetDownloadedHandler.cls`:**

Add `is_first_customer_pull` check early in the per-event loop. When `is_first_customer_pull` is `false`, skip Lead conversion and Account creation — the customer already has an active deployment. This makes the handler's intent explicit rather than relying solely on the Account-exists idempotency check.

```apex
// After parsing data:
Boolean isFirstPull = data.get('is_first_customer_pull') == true;
if (!isFirstPull) {
    continue; // Only process first-pull events
}
```

The existing Account-exists idempotency check remains as a safety net (handles cases where `is_first_customer_pull` might lag behind actual state).

**Test updates** — `AssetDownloadedHandlerTest.cls`:
- Add `"is_first_customer_pull": true` to all existing test payloads (they currently test first-pull behavior)
- Add `testSubsequentPullSkipped` — payload with `"is_first_customer_pull": false` → no Lead conversion, no Account creation

### Phase 2: Add Enterprise Portal event handling

Add end-to-end support for the three EP events across all four layers (subscription → trigger → handler → tests).

#### 2a. Subscription script

**`hack/setup-webhook-subscription`** — add three new event configs:

```bash
{ eventType: "customer.ep_invite_sent",    filters: {} },
{ eventType: "customer.ep_access_granted", filters: {} },
{ eventType: "customer.ep_user_joined",    filters: {} },
```

**Subscription update mechanism**: The script currently exits early if a subscription named "Salesforce CRM Sync" already exists. Add a `--recreate` flag that deletes the existing subscription before creating the new one. The script already has the subscription ID from the lookup query — use `replicated api delete /v3/notification_subscription/$id` before proceeding with creation. Document that operators should run `make webhook-subscription RECREATE=1` after updating event configs.

#### 2b. Trigger routing

**`ReplicatedWebhookSubscriber.trigger`** — add a new collection and routing case:

```apex
List<Replicated_Webhook__e> epEvents = new List<Replicated_Webhook__e>();

// Inside switch:
when 'customer.ep_invite_sent', 'customer.ep_access_granted', 'customer.ep_user_joined' {
    epEvents.add(event);
}

// After the switch loop:
if (!epEvents.isEmpty()) {
    System.enqueueJob(new EnterprisePortalEventHandler(epEvents));
}
```

All three EP events route to a single handler because they share the same processing pattern (look up Account by customer ID, create a Task on the Account owner).

#### 2c. Handler class

**New file: `create-license/main/default/classes/EnterprisePortalEventHandler.cls`**

```apex
public without sharing class EnterprisePortalEventHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public EnterprisePortalEventHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Parse payloads from Payload__c JSON. Extract:
        //   - event (top-level): event type key for routing
        //   - data.customer_id: Account lookup key
        //   - data.customer_name: Task description
        //   - Event-specific fields from data:
        //     ep_invite_sent:    invited_email, is_first_user
        //     ep_access_granted: activated_email, access_method
        //     ep_user_joined:    joined_email, access_method, is_first_user
        //
        // Dedup by customer_id + event_type within batch.
        // Bulk query Accounts by Replicated_Customer_Id__c.
        //
        // Create Tasks on Account owner with event-specific subjects:
        //   ep_invite_sent    → "EP invite sent to {invited_email} for {customer_name}"
        //   ep_access_granted → "EP access granted for {customer_name} via {access_method}"
        //   ep_user_joined    → "{joined_email} joined EP for {customer_name}"
        //
        // SyncGuard: not needed for Task-only DML (no outbound Task triggers exist).
    }
}
```

Pattern follows established conventions:
- `without sharing` (system-to-system handler)
- Constructor takes `List<Replicated_Webhook__e>`
- Parse from `Payload__c` JSON (same pattern as `AssetDownloadedHandler`, `TrialSignupHandler`)
- Bulk SOQL with `WHERE field IN :collection`
- Bulk DML (list-based)
- Within-batch deduplication via `Set<String>` keyed on `customer_id + event_type`
- Task-only approach matches `LicenseExpiringHandler` pattern (no idempotency for retries — consistent with existing design)

**New file: `create-license/main/default/classes/EnterprisePortalEventHandler.cls-meta.xml`**

Standard Apex class metadata (API version 61.0, status Active).

#### 2d. Test class

**New file: `create-license/main/default/classes/EnterprisePortalEventHandlerTest.cls`**

Test cases:
- `testEpInviteSentCreatesTask` — happy path for invite event
- `testEpAccessGrantedCreatesTask` — happy path for access granted
- `testEpUserJoinedCreatesTask` — happy path for user joined
- `testNoMatchingAccount` — event for unknown customer_id → no DML, no exception
- `testMalformedPayload` — invalid JSON → graceful skip
- `testBulkEpEvents` — 200 mixed EP events → stays within governor limits

**New file: `create-license/main/default/classes/EnterprisePortalEventHandlerTest.cls-meta.xml`**

Standard test metadata.

### Phase 3: Add `customer.updated` handler

Add a handler that syncs customer field changes from Replicated back to the Salesforce Account.

#### 3a. Trigger routing

**`ReplicatedWebhookSubscriber.trigger`** — add a new collection and routing case:

```apex
List<Replicated_Webhook__e> customerUpdatedEvents = new List<Replicated_Webhook__e>();

// Inside switch:
when 'customer.updated' {
    customerUpdatedEvents.add(event);
}

// After the switch loop:
if (!customerUpdatedEvents.isEmpty()) {
    System.enqueueJob(new CustomerUpdatedHandler(customerUpdatedEvents));
}
```

#### 3b. Handler class

**New file: `create-license/main/default/classes/CustomerUpdatedHandler.cls`**

Syncs changed customer fields to the matching Account:
- `customer_name` → `Account.Name` (only if `old_customer_name` differs)
- `license_type` → `Account.Replicated_License_Type__c` (only if `old_license_type` differs)
- `channel_name` → `Account.Replicated_Channel__c` (only if `channel_changed`)
- `expires_at` → `Account.Replicated_License_Expiry__c` (only if `expiration_changed`)

Pattern:
- Parse `Payload__c` JSON for the change-tracking fields (`old_*`, `*_changed`)
- Only update fields that actually changed (check `old_*` presence or `*_changed` flag)
- Look up Account by `Replicated_Customer_Id__c`
- `SyncGuard.inboundSyncIds.add(acc.Id)` BEFORE the Account update DML
- Skip if no Account exists for `customer_id` (customer hasn't been provisioned in SF yet)

#### 3c. Test class

**New file: `create-license/main/default/classes/CustomerUpdatedHandlerTest.cls`**

Test cases:
- `testNameChange` — `old_customer_name` set, Account.Name updated
- `testLicenseTypeChange` — `old_license_type` set, Account.Replicated_License_Type__c updated
- `testExpiryChange` — `expiration_changed: true`, Account.Replicated_License_Expiry__c updated
- `testChannelChange` — `channel_changed: true`, Account.Replicated_Channel__c updated
- `testNoChanges` — no `old_*` or `*_changed` fields → no DML
- `testNoMatchingAccount` — no Account for customer_id → no DML, no exception
- `testSyncGuardPreventsLoop` — verify SyncGuard.inboundSyncIds contains Account ID after update
- `testBulkCustomerUpdates` — 200 events → stays within governor limits

## Confirmed Payload Schemas (from `replicatedhq/vandoor`)

All payloads follow the standard envelope: `{"event": "<key>", "timestamp": "...", "text": "...", "data": {...}}`. The `data` object contains all fields from the SQS event struct plus `eventType` (duplicated from top-level `event`). The `RenderWebhookPayload` method copies all eventData fields verbatim into `data`.

### `customer.ep_invite_sent` (`CustomerEPInviteSentEvent`)

| Field | Type | Description |
|---|---|---|
| `event_type` | string | `"customer.ep_invite_sent"` |
| `team_id` | string | Replicated team ID |
| `customer_id` | string | Replicated customer ID |
| `customer_name` | string | Customer name |
| `app_id` | string | Application ID |
| `app_name` | string | Application name |
| `app_slug` | string | Application slug |
| `invited_email` | string | Email address invited to EP |
| `is_first_user` | boolean | True if this is the first EP user for this customer |
| `license_type` | string | `"paid"`, `"trial"`, `"community"`, `"dev"` |
| `sent_at` | ISO-8601 | When the invite was sent |

### `customer.ep_access_granted` (`CustomerEPAccessGrantedEvent`)

Description: "When the first user activates on an Enterprise Portal customer (revenue recognition milestone)"

| Field | Type | Description |
|---|---|---|
| `event_type` | string | `"customer.ep_access_granted"` |
| `team_id` | string | Replicated team ID |
| `customer_id` | string | Replicated customer ID |
| `customer_name` | string | Customer name |
| `app_id` | string | Application ID |
| `app_name` | string | Application name |
| `app_slug` | string | Application slug |
| `activated_email` | string | Email of the user who activated access |
| `access_method` | string | `"invite"`, `"self_signup"`, or `"saml_jit"` |
| `license_type` | string | `"paid"`, `"trial"`, `"community"`, `"dev"` |
| `granted_at` | ISO-8601 | When access was granted |

### `customer.ep_user_joined` (`CustomerEPUserJoinedEvent`)

| Field | Type | Description |
|---|---|---|
| `event_type` | string | `"customer.ep_user_joined"` |
| `team_id` | string | Replicated team ID |
| `customer_id` | string | Replicated customer ID |
| `customer_name` | string | Customer name |
| `app_id` | string | Application ID |
| `app_name` | string | Application name |
| `app_slug` | string | Application slug |
| `joined_email` | string | Email of the user who joined |
| `access_method` | string | `"invite"`, `"self_signup"`, or `"saml_jit"` |
| `is_first_user` | boolean | True if this is the first EP user for this customer |
| `license_type` | string | `"paid"`, `"trial"`, `"community"`, `"dev"` |
| `joined_at` | ISO-8601 | When the user joined |

### `release.asset_downloaded` (`AssetDownloadedEvent`)

| Field | Type | Description |
|---|---|---|
| `event_type` | string | `"release.asset_downloaded"` |
| `team_id` | string | Replicated team ID |
| `customer_id` | string | Replicated customer ID |
| `customer_name` | string | Customer name |
| `service_account_name` | string | EP service account that pulled (empty if via license) |
| `app_id` | string | Application ID |
| `app_name` | string | Application name |
| `app_slug` | string | Application slug |
| `channel_id` | string | Release channel ID |
| `channel_name` | string | Release channel name |
| `asset_type` | string | `"helm_chart"`, `"embedded_cluster_bundle"`, `"proxy_image"` |
| `asset_name` | string | Name of the chart/asset |
| `asset_version` | string | Version/tag of the asset |
| `license_type` | string | `"paid"`, `"trial"`, `"community"`, `"dev"` |
| `downloaded_at` | ISO-8601 | When the download occurred |
| `is_first_customer_pull` | boolean | True when this is the first completed software pull for the customer across all asset types |

### `customer.updated` (`CustomerUpdatedEvent`)

Rich change-tracking payload with old/new values:

| Field | Type | Description |
|---|---|---|
| `event_type` | string | `"customer.updated"` |
| `team_id` | string | Replicated team ID |
| `customer_id` | string | Replicated customer ID |
| `customer_name` | string | Current customer name |
| `old_customer_name` | string | Previous name (if changed) |
| `app_id` | string | Application ID |
| `app_name` | string | Application name |
| `app_slug` | string | Application slug |
| `license_type` | string | Current license type |
| `old_license_type` | string | Previous license type (if changed) |
| `expires_at` | ISO-8601 | Current expiry (null = perpetual) |
| `old_expires_at` | ISO-8601 | Previous expiry (if changed) |
| `expiration_changed` | boolean | True if expiration changed |
| `channel_id` | string | Current channel ID |
| `channel_name` | string | Current channel name |
| `old_channel_id` | string | Previous channel ID (if changed) |
| `old_channel_name` | string | Previous channel name (if changed) |
| `channel_changed` | boolean | True if channel changed |
| `helm_email` | string | Current Helm email |
| `old_helm_email` | string | Previous Helm email (if changed) |
| `changed_install_options` | array | List of `{name, old_value, new_value}` |
| `changed_entitlements` | array | List of `{name, old_value, new_value}` |
| `updated_at` | ISO-8601 | When the update occurred |

## Technical Considerations

- **EP payloads confirmed.** All three EP events include `customer_id` in the standard location (`data.customer_id`). The `ReplicatedWebhookReceiver` will correctly populate `Customer_Id__c` on the Platform Event. Parse from `Payload__c` for event-specific fields (`invited_email`, `activated_email`, `joined_email`, `access_method`, `is_first_user`).

- **Task-only approach for initial implementation.** All three EP events create Tasks rather than updating Account fields. This avoids schema changes (new fields, FLS on 5+ profiles, layout updates) and is consistent with `LicenseExpiringHandler`. Account field updates (`EP_Access_Granted__c`, `EP_Access_Date__c`) can be added as a follow-on when EP status reporting needs emerge.

- **Governor limits.** Adding a sixth `System.enqueueJob()` call in the trigger is fine — the limit is 50 per transaction, and the trigger currently uses at most 5.

- **Naming convention adherence.** All event type strings must be copy-pasted from the canonical reference (lines 93-113 of `docs/solutions/integration-issues/webhook-event-type-naming-mismatch.md`). The same string must appear in: subscription config, trigger `switch on` case, handler conditional (if applicable), and test fixtures.

- **Phase 1 activation risk.** The naming fix will cause `TrialSignupHandler` and `AssetDownloadedHandler` to start processing events for the first time. Platform Events have a 24-hour retention window, so there is no risk of a massive backlog replay. However, any events received in the last 24 hours will be processed on the next replay cycle after deployment.

## System-Wide Impact

- **Interaction graph**: Webhook POST → `ReplicatedWebhookReceiver` → `Replicated_Webhook__e` → `ReplicatedWebhookSubscriber` trigger → `EnterprisePortalEventHandler` Queueable → Task DML (no outbound Task triggers, no SyncGuard needed)
- **Error propagation**: Malformed payloads are caught in the handler and logged; no Account found for `customer_id` means no DML (safe). DML failures are caught and logged.
- **State lifecycle risks**: Minimal — EP events create Tasks only. No multi-object transaction chains, no echo loop risk.
- **API surface parity**: The naming fix in Phase 1 aligns trigger routing with the subscription script and canonical API. No new API surfaces.

## Acceptance Criteria

### Phase 1
- [ ] Trigger routes `'customer.pending_signup'` (not display name) to `TrialSignupHandler`
- [ ] Trigger routes `'release.asset_downloaded'` (not display name) to `AssetDownloadedHandler`
- [ ] All test fixtures use canonical event type keys
- [ ] Code examples in `docs/solutions/integration-issues/trial-handler-bulkification-governor-limit.md` use canonical keys

### Phase 1b
- [ ] `AssetDownloadedHandler` checks `is_first_customer_pull` from payload and skips non-first-pull events
- [ ] Existing test payloads include `"is_first_customer_pull": true`
- [ ] New test `testSubsequentPullSkipped` verifies non-first-pull events are ignored

### Phase 2
- [ ] Subscription script includes `customer.ep_invite_sent`, `customer.ep_access_granted`, `customer.ep_user_joined`
- [ ] Subscription script supports `--recreate` flag for updating existing subscriptions
- [ ] Trigger routes all three EP events to `EnterprisePortalEventHandler`
- [ ] `EnterprisePortalEventHandler` creates Tasks on Account owners with event-specific details (invited_email, activated_email, joined_email, access_method)
- [ ] Test class covers happy path for each EP event type + no matching account + malformed payload + bulk test
- [ ] `make deploy` succeeds
- [ ] All existing tests continue to pass

### Phase 3
- [ ] Trigger routes `'customer.updated'` to `CustomerUpdatedHandler`
- [ ] Handler syncs changed fields (name, license type, channel, expiry) to Account
- [ ] Handler uses change-tracking fields (`old_*`, `*_changed`) to avoid unnecessary updates
- [ ] SyncGuard applied before Account update DML
- [ ] Test class covers individual field changes, no-change no-op, no matching account, SyncGuard, and bulk events

## Success Metrics

- Zero events silently dropped in the `when else` branch for subscribed event types
- EP lifecycle events visible in Salesforce as Tasks on Account owners
- All 11 subscribed event types (8 existing + 3 EP) have corresponding trigger routing and handlers
- Customer field changes in Replicated sync back to Salesforce Accounts

## Resolved Questions

1. **EP event payload structure** — **Resolved.** All three EP events confirmed to include `customer_id`, `customer_name`, `app_id`, `app_name`, `app_slug`, `license_type` in the standard location. Event-specific fields: `invited_email` / `is_first_user` (invite), `activated_email` / `access_method` (access granted), `joined_email` / `access_method` / `is_first_user` (user joined). Source: `replicatedhq/vandoor` `pkg/notifications/events/`.
2. **`customer.updated` disposition** — **Resolved: Add a handler.** Phase 3 added to sync changed customer fields back to Account using the rich change-tracking payload.
3. **`is_first_customer_pull`** — **Resolved: Field exists.** It is a boolean in the `release.asset_downloaded` payload. Phase 1b added to use this field in `AssetDownloadedHandler`.

## Dependencies & Risks

- **EP payload structure confirmed** from vandoor source. No prerequisite capture step needed.
- **Subscription recreation gap**: When the `--recreate` flag deletes and recreates the subscription, there is a brief window where no subscription exists. Events during this window would be lost. Mitigate by running during low-traffic periods.
- **Phase 1 enables previously-dead handlers**: After fixing the naming mismatches, `TrialSignupHandler` and `AssetDownloadedHandler` will process events for the first time. Platform Event 24-hour retention limits the blast radius.

## Sources & References

- Canonical event types: `docs/solutions/integration-issues/webhook-event-type-naming-mismatch.md` (lines 93-113)
- Handler pattern: `docs/solutions/integration-issues/trial-handler-bulkification-governor-limit.md`
- SyncGuard pattern: `docs/solutions/integration-issues/bidirectional-sync-loop-prevention.md`
- Webhook architecture: `docs/solutions/integration-issues/webhook-receiver-hmac-verification.md`
- EP setup script: `hack/setup-enterprise-portal`
- EP event structs: `replicatedhq/vandoor` `pkg/notifications/events/customer_ep_invite_sent.go`, `customer_ep_access_granted.go`, `customer_ep_user_joined.go`
- Asset downloaded struct: `replicatedhq/vandoor` `pkg/notifications/events/asset_downloaded.go` (confirms `is_first_customer_pull` field)
- Customer updated struct: `replicatedhq/vandoor` `pkg/notifications/events/customer_updated.go` (confirms change-tracking payload)
- Event interface and registry: `replicatedhq/vandoor` `pkg/notifications/events/event.go`
- Related PRs: #67 (webhook subscription automation), #51 (instance and license event handlers), #66 (Enterprise Portal configuration)
