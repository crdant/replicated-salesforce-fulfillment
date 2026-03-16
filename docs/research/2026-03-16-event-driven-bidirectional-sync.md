---
date: 2026-03-16T12:00:00-04:00
researcher: Claude
git_commit: 7cba8d10feea7293a6d3247a8a66603c327438f4
branch: main
repository: crdant/cold-leads-to-hot-signal
topic: "Event-driven bidirectional sync between Salesforce and Replicated Platform"
tags: [research, codebase, salesforce, replicated, webhooks, platform-events, event-driven, bidirectional-sync]
status: complete
last_updated: 2026-03-16
last_updated_by: Claude
last_updated_note: "All design decisions resolved — 10 decisions documented, no remaining open questions"
---

# Research: Event-Driven Bidirectional Sync Between Salesforce and Replicated Platform

**Date**: 2026-03-16T12:00:00-04:00
**Researcher**: Claude
**Git Commit**: 7cba8d10feea7293a6d3247a8a66603c327438f4
**Branch**: main
**Repository**: crdant/cold-leads-to-hot-signal

## Research Question

How to convert the existing Salesforce-to-Replicated fulfillment flow into an event-driven, bidirectional sync where Salesforce accurately reflects ground truth from the Replicated Platform and Replicated reflects changes originating in Salesforce.

## Summary

The current implementation is a **one-directional, trigger-based flow**: Salesforce Order activation fires a trigger chain that calls the Replicated API to create/update licenses and deliver install instructions. There is no mechanism for Replicated events (signups, activations, downloads, license expiry, usage metrics) to flow back into Salesforce.

The User Story (`docs/User Story.md`) describes 8 capabilities needed for a self-service trial workflow. All are available today via Replicated's Event Notifications webhooks and Vendor API v3, except custom metrics threshold alerting (in-progress).

To make this bidirectional, the architecture needs:

1. **Inbound (Replicated → Salesforce)**: An Apex REST endpoint receives Replicated webhooks, verifies HMAC signatures, and publishes Salesforce Platform Events for async processing
2. **Outbound (Salesforce → Replicated)**: Change Data Capture or object triggers detect Salesforce changes and enqueue Queueable callouts to the Replicated API
3. **Loop prevention**: A sync guard mechanism prevents infinite loops when inbound updates trigger outbound triggers

## Detailed Findings

### Current Architecture

The existing codebase implements a linear fulfillment pipeline:

```
Contract Activated
  → CloseWonOpportunity trigger (sets Opportunity to "Closed Won")
  → ActivateOrder trigger (sets Order status to "Activated")
    → FulfillOrder trigger (enqueues ReplicatedFulfillment Queueable)
      → ReplicatedFulfillment.execute():
        1. Search/create customer via Replicated API (custom_id = SF Account ID)
        2. Download license file
        3. Load application and channel metadata
        4. Generate install instructions (Helm, Airgap, EC, KOTS)
        5. Attach license + instructions to Order
        6. Email customer
```

**Key classes and their roles:**

| Class | Role | Lines |
|---|---|---|
| `ReplicatedPlatform.cls` | HTTP client for Replicated Vendor API v3 | 251 |
| `ReplicatedFulfillment.cls` | Queueable orchestrator for the fulfillment pipeline | 170 |
| `ReplicatedCustomer.cls` | Data model mapping OrderTerms to Replicated customer fields | 110 |
| `OrderTerms.cls` | Extracts order/license details from Opportunity + Products | 170 |
| `ReplicatedInstallInstructions.cls` | Generates install instructions from app/channel/customer data | 172 |
| `ReplicatedApplication.cls` | Data model for Replicated application | 12 |
| `ReplicatedChannel.cls` | Data model for Replicated channel | 7 |
| `ReplicatedLicenseEntitlement.cls` | Data model for license entitlements | 15 |

**Custom Salesforce objects/fields:**

- `Product2.Application__c` — Replicated app ID
- `Product2.ReleaseChannel__c` — Replicated channel ID
- `Product2.IsAdminConsoleEnabled__c`, `IsAirgapEnabled__c`, `IsEmbeddedClusterEnabled__c`, `IsAddOn__c`, `IsSnapshotSupported__c`, `IsSupportBundleUploadEnabled__c` — Replicated entitlement flags
- `Order.LicenseId__c` — Stores the generated Replicated license ID
- `Replicated_Vendor_Portal_API_Credential__mdt` — API token storage

**Triggers:**

- `CloseWonOpportunity` on Contract (after update) — Closes the Opportunity when Contract activates
- `ActivateOrder` on Contract (after update) — Activates the Order when Contract activates
- `FulfillOrder` on Order (after update) — Enqueues fulfillment when Order activates

### Replicated Event Notifications (Webhooks)

Replicated's Event Notifications system (Beta) supports 20+ event types across five categories. The events most relevant to the User Story's self-service trial flow:

| Event | Trigger | Salesforce Action |
|---|---|---|
| `Pending Self-Service Signup` | Prospect submits sign-up form | Create Lead or Task |
| `customer.created` | Prospect confirms email, customer record created | Create/update Account, Contact, Opportunity |
| `Customer release asset downloads` | Customer pulls release assets | Log Activity on Account |
| `Customer License Expiring` | Configurable days-before-expiry | Create Task for sales team |
| `Customer Updated` | License/entitlement changes | Sync changes to Account/Order |
| `Instance Created` | New instance reports in | Update Account with instance data |
| `Instance Upgraded` | Instance upgrades to new version | Log Activity |
| `Instance Inactive` | No check-in for 24 hours | Create alert Task |
| `Custom Metric Threshold Reached` | Metric crosses threshold (coming soon) | Notify sales of adoption signal |

**Webhook payload structure:**

```json
{
  "event": "customer.created",
  "timestamp": "2026-01-25T22:48:32Z",
  "text": "Human-readable description",
  "data": {
    "app_id": "...",
    "team_id": "...",
    "customer_id": "...",
    "customer_name": "...",
    "channel_id": "...",
    "license_type": "trial",
    "expires_at": "2026-02-24T22:47:37Z",
    "subscription_name": "..."
  }
}
```

**Webhook security:**
- HMAC-SHA256 signature in `X-Replicated-Signature: sha256=<hex>` header
- Up to 5 custom auth headers per subscription (encrypted at rest)
- 5-second timeout, 8 retries with exponential backoff
- Auto-disables after 10 consecutive permanent failures

### Replicated Vendor API v3 (Outbound Sync Endpoints)

**Base URL**: `https://api.replicated.com/vendor/v3`

Key endpoints the project already uses:
- `POST /customers/search` — Search by `customId` (Salesforce Account ID)
- `POST /customer` — Create customer/license
- `PUT /customer` — Update customer/license
- `GET /app/{app_id}/customer/{customer_id}/license-download` — Download license YAML
- `GET /app/{app_id}` — Load application details
- `GET /app/{app_id}/channel/{channel_id}` — Load channel details

Key endpoints needed for bidirectional sync:
- `GET /app/{app_id}/customer_instances` — Export 60+ fields (CSV/JSON) for bulk sync
- `GET /app/{app_id}/events` — Historical timeseries with custom metrics
- `GET /customer/{customer_id}/instance` — List instances for a customer
- `PATCH /customer/{customer_id}` — Partial update (safer than PUT for sync)
- `POST /customer/{customer_id}/archive` — Archive when Account is deactivated

The `custom_id` field on Replicated customers is designed specifically for CRM reconciliation. The existing code already sets this to the Salesforce Account ID.

### Salesforce Event-Driven Architecture Components

#### Apex REST Resources (Inbound Webhook Receiver)

Salesforce doesn't natively expose webhook endpoints. Create a custom `@RestResource` exposed through a Salesforce Site:

```apex
@RestResource(urlMapping='/replicated/webhook')
global without sharing class ReplicatedWebhookReceiver {
    @HttpPost
    global static void handleWebhook() {
        // 1. Verify HMAC-SHA256 signature
        // 2. Parse payload
        // 3. Publish Platform Event for async processing
        // 4. Return 200
    }
}
```

The webhook URL would be: `https://<site-domain>/services/apexrest/replicated/webhook`

HMAC verification uses `Crypto.generateMac('HmacSHA256', body, secret)` in Apex.

#### Platform Events (Internal Event Bus)

Define a `Replicated_Webhook__e` Platform Event to decouple webhook receipt from processing:

- `Event_Type__c` (Text) — e.g., `customer.created`
- `Payload__c` (Long Text Area) — Raw JSON payload
- `Customer_Id__c` (Text) — Replicated customer ID for routing

Platform Event triggers (`after insert` only) subscribe to these events and enqueue Queueable jobs for processing. This pattern:
- Returns 200 to Replicated quickly (within the 5-second timeout)
- Provides 72-hour replay on failure
- Supports multiple independent subscribers

#### Change Data Capture (Outbound Change Detection)

CDC on Account, Opportunity, and Order detects changes and can trigger outbound sync to Replicated:

- `AccountChangeEvent` — Sync name/email changes to Replicated customer
- `OpportunityChangeEvent` — Sync stage changes, entitlement updates
- `OrderChangeEvent` — Sync license term changes

CDC provides `header.commitUser` to identify who made the change, enabling loop prevention by skipping changes made by the integration user.

#### Loop Prevention Strategies

Three complementary approaches:

1. **Static Set Guard** — `SyncGuard.inboundSyncIds` tracks records being updated by inbound webhooks so outbound triggers skip them. Works within a single transaction.

2. **Integration User Detection** — CDC triggers check `header.commitUser` and skip changes made by the integration/API user. Works across transactions.

3. **`Last_Synced_By__c` Field** — A custom field set to `'Replicated'` during inbound sync. Outbound triggers check this and skip. Most durable (persists across transaction boundaries).

### Proposed Architecture

#### Inbound Flow (Replicated → Salesforce)

```
Replicated Webhook POST
  → Salesforce Site URL
  → ReplicatedWebhookReceiver (@RestResource)
    → HMAC-SHA256 verification
    → Log to Webhook_Event__c (audit)
    → Publish Replicated_Webhook__e (Platform Event)
      → ReplicatedWebhookSubscriber trigger (after insert)
        → Route by event type:
          - customer.created → Create/update Account + Contact
          - license.expiring → Create Task for sales
          - asset.downloaded → Log Activity
          - instance.created → Update Account with instance data
          - custom_metric.threshold → Notify sales
        → Enqueue appropriate Queueable handler
        → Set SyncGuard / Last_Synced_By__c
```

#### Outbound Flow (Salesforce → Replicated)

```
User modifies Account/Opportunity/Order
  → CDC trigger (e.g., AccountChangeEvent)
    → Check commitUser ≠ integration user
    → Check changedFields contains relevant fields
    → Enqueue ReplicatedOutboundSync Queueable
      → PATCH /vendor/v3/customer/{id} (partial update)
```

Or extending the existing trigger pattern:
```
User activates Order
  → FulfillOrder trigger (existing)
    → Check SyncGuard.inboundSyncIds
    → Enqueue ReplicatedFulfillment (existing)
```

#### New Salesforce Components Needed

```
create-license/main/default/
  classes/
    ReplicatedWebhookReceiver.cls          — @RestResource endpoint
    ReplicatedWebhookProcessor.cls         — Queueable for inbound event processing
    ReplicatedOutboundSync.cls             — Queueable for outbound sync
    SyncGuard.cls                          — Static recursion guard
  objects/
    Replicated_Webhook__e/                 — Platform Event definition
      Replicated_Webhook__e.object-meta.xml
      fields/
        Event_Type__c.field-meta.xml
        Payload__c.field-meta.xml
        Customer_Id__c.field-meta.xml
    Replicated_Webhook_Secret__mdt/        — Webhook signing secret
    Webhook_Event__c/                      — Audit log for inbound webhooks
    Account/fields/
      Replicated_Customer_Id__c            — Links Account to Replicated customer
      Last_Synced_By__c                    — Loop prevention field
  triggers/
    ReplicatedWebhookSubscriber.trigger    — Platform Event subscriber
```

### Mapping User Story Steps to Implementation

| Step | Direction | Mechanism | New/Existing |
|---|---|---|---|
| 1. Branded sign-up page | N/A | Replicated Enterprise Portal (external) | External |
| 2. Notified on signup | Inbound | `Pending Self-Service Signup` webhook → Lead/Task | New |
| 3. Notified on activation | Inbound | `customer.created` webhook → Account/Contact | New |
| 4. Know about downloads | Inbound | `Asset Downloaded` webhook → Activity | New |
| 5. CRM visibility + trial expiration | Both | Webhooks (real-time) + API export (batch) | New inbound + extend existing |
| 6. Notified before expiry | Inbound | `License Expiring` webhook → Task | New |
| 7. Product usage visibility | Inbound | Custom metrics via API export + threshold webhooks (coming soon) | New |
| 8. Access revoked on expiry | N/A | Automatic via Replicated (registry block + SDK API) | External |

### Infrastructure Considerations

**Named Credentials**: The current implementation hardcodes the Replicated API URL and stores the token in Custom Metadata. Recommend migrating to Named Credentials:
- Endpoint: `callout:Replicated_Vendor_Portal/vendor/v3/...`
- Credentials injected automatically, rotatable without code changes
- Eliminates the Remote Site Setting

**Salesforce Site Setup**: Required for the inbound webhook endpoint:
- Create a Salesforce Site (Setup → Sites)
- Grant Site Guest User profile access to `ReplicatedWebhookReceiver` Apex class
- Grant CRUD on `Webhook_Event__c` and publish access on `Replicated_Webhook__e`
- Optionally restrict by IP range

**Replicated Webhook Configuration**: Done in the Vendor Portal UI:
- Navigate to Notifications → Create Notification
- Select relevant event types
- Set webhook URL to `https://<site-domain>/services/apexrest/replicated/webhook`
- Configure signing secret for HMAC verification
- Optionally add custom headers for additional auth

## Code References

- `create-license/main/default/classes/ReplicatedPlatform.cls` — HTTP client for Replicated API (all callouts)
- `create-license/main/default/classes/ReplicatedFulfillment.cls` — Fulfillment orchestrator (Queueable)
- `create-license/main/default/classes/ReplicatedCustomer.cls` — Customer data model with `custom_id` = SF Account ID
- `create-license/main/default/classes/OrderTerms.cls` — Extracts terms from Opportunity/Products
- `create-license/main/default/triggers/FulfillOrder.trigger` — Entry point for existing flow
- `create-license/main/default/triggers/ActivateOrder.trigger` — Contract → Order activation
- `create-license/main/default/triggers/CloseWonOpportunity.trigger` — Contract → Opportunity close
- `create-license/main/default/objects/Order/fields/LicenseId__c.field-meta.xml` — License ID on Order
- `create-license/main/default/objects/Product2/fields/Application__c.field-meta.xml` — Replicated app ID on Product
- `create-license/main/default/remoteSiteSettings/ReplicatedVendorPortal.remoteSite-meta.xml` — Remote site for API access

## Architecture Insights

1. **The `custom_id` field is the reconciliation key.** The existing code already maps Salesforce Account ID to Replicated `custom_id` (`ReplicatedPlatform.cls:149`), which is specifically designed for CRM integration. This is the bidirectional join key.

2. **The Queueable pattern is correct and should be extended.** The existing `FulfillOrder trigger → ReplicatedFulfillment Queueable` pattern is the right approach for Salesforce callouts. New inbound and outbound handlers should follow the same pattern.

3. **Platform Events over Outbound Messages.** Salesforce is deprecating Workflow Rules (which power Outbound Messages). Platform Events are the modern replacement with REST support, multiple subscribers, and 72-hour replay.

4. **CDC is preferred over object triggers for outbound sync.** CDC runs asynchronously after commit, provides `changedFields` for selective sync, and includes `commitUser` for loop prevention. Object triggers require manual recursion guards.

5. **HMAC verification is straightforward in Apex.** The `Crypto.generateMac('HmacSHA256', ...)` method and `EncodingUtil.convertToHex()` map directly to Replicated's `X-Replicated-Signature: sha256=<hex>` format.

6. **The 5-second webhook timeout is tight.** The Apex REST endpoint must respond within 5 seconds. The Platform Event pattern (receive → verify → publish → return 200) keeps the synchronous path fast while deferring heavy processing.

7. **Partial update (PATCH) is safer for outbound sync.** The existing code uses PUT for customer updates, which replaces the entire customer object. For bidirectional sync, PATCH at `PATCH /vendor/v3/app/{app_id}/customer/{customer_id}` only changes provided fields, reducing the risk of overwriting data set by other systems.

## Design Decisions

1. **Self-service trial signup → Create a Lead.** The `Pending Self-Service Signup` webhook creates a Lead. The Lead is enriched on `customer.created` with Replicated customer ID, license type, expiration, and channel. The Lead converts to Account + Contact + Opportunity on `Release Assets Downloaded` — this is the strongest pre-instance signal that the prospect is engaged. If an instance never comes up after download, that gap is itself an actionable signal for SDR follow-up.

2. **Instance data stored on a custom object (`Replicated_Instance__c`) associated with Account.** Instances belong to the Account as the durable parent (not the Opportunity, which may close before interesting instance data arrives). Instance data is surfaced on the Opportunity page layout via the Account relationship (Option B — Account-only with related list/component on Opportunity).

3. **Custom metrics: `daily_active_users` and `monthly_active_users`.** The demo uses Slackernews, which already reports these. These are sufficient for sales-relevant adoption signals. Custom metrics threshold alerting (when it ships) can notify sales when usage crosses thresholds.

4. **Webhooks only, no batch export.** For the demo, real-time webhook delivery is sufficient. No scheduled batch reconciliation job.

5. **License enforcement via `crdant/replicated-license-enforcer` sidecar.** Out of scope for this project — referenced as a dependency in the demo plan. Known improvement needed: make the public key runtime-configurable (currently hardcoded in `pkg/client/public_key.go`), which currently requires forking to use with a different account.

6. **Enterprise Portal replaces the fulfillment email flow entirely.** Both self-service trials and sales-led deals use the Enterprise Portal for delivery (install instructions, license, release assets). The existing `ReplicatedInstallInstructions` class, file attachment logic, and email sending in `ReplicatedFulfillment` are no longer needed. Fulfillment simplifies to: create/update the Replicated customer, then invite them to the Enterprise Portal via API.

7. **Enterprise Portal invite is a separate API call, not automatic.** Creating a customer via `POST /vendor/v3/customer` does NOT grant portal access. Two steps are needed:
   - **One-time setup**: `PUT /app/{app_id}/enterprise-portal/status` with `{"status": "always"}` to enable the portal for all customers (alternatives: `"never"`, `"per-customer"`)
   - **Per-customer invite**: `POST /app/{app_id}/enterprise-portal/customer-user` with `{"customer_id": "...", "email_address": "..."}` — sends the invite email automatically
   - For self-service trials, this is handled automatically (user signed up through the portal). For sales-led deals, the fulfillment flow adds the invite call after customer creation.

8. **Salesforce Developer Edition org is sufficient.** Developer Edition includes Platform Events and CDC. The dev org at `shortriblabs-dev-ed.develop.my.salesforce.com` supports the full architecture.

9. **A Salesforce Site needs to be created.** No existing Site is configured. A Site is required to expose a public URL for the `@RestResource` webhook endpoint so Replicated can POST to it without Salesforce OAuth. This is a setup/configuration step, not code.

10. **`Replicated_Instance__c` custom object fields — all read-only in Salesforce.** Replicated is the source of truth for instance data. Salesforce displays it but never writes back. Fields:

    | Field | Type | Description |
    |---|---|---|
    | `Instance_Id__c` | Text (External ID) | Replicated instance ID — reconciliation key |
    | `Status__c` | Picklist | Ready / Updating / Degraded / Unavailable / Missing |
    | `App_Version__c` | Text | Running application version |
    | `First_Check_In__c` | DateTime | First instance check-in — measures time-to-install |
    | `Last_Check_In__c` | DateTime | Last instance check-in — measures engagement recency |
    | `Cloud_Provider__c` | Text | AWS / GCP / Azure / etc. |
    | `K8s_Distribution__c` | Text | Kubernetes distribution |
    | `Daily_Active_Users__c` | Number | Slackernews custom metric |
    | `Monthly_Active_Users__c` | Number | Slackernews custom metric |
