---
date: 2026-03-19T12:00:00-04:00
researcher: Claude
git_commit: 4c883f9
branch: main
repository: crdant/replicated-salesforce-fulfillment
topic: "Replicated webhook notification inventory: events, affected objects, and state changes"
tags: [research, codebase, webhooks, platform-events, notification-handling]
status: complete
last_updated: 2026-03-19
last_updated_by: Claude
last_updated_note: "Added revised notification design based on EP user joined conversion and paid download fulfillment"
---

# Research: Replicated Webhook Notification Inventory

**Date**: 2026-03-19
**Researcher**: Claude
**Git Commit**: 4c883f9
**Branch**: main
**Repository**: crdant/replicated-salesforce-fulfillment

## Research Question

Document each Replicated notification we receive, the Salesforce object it affects, and the state change it creates.

## Summary

The system handles 7 distinct webhook event types, routed through a `Replicated_Webhook__e` Platform Event to 5 handler classes. These handlers modify 5 Salesforce objects: Lead, Account, Contact, Opportunity, Replicated_Instance__c, and Task.

## Current Notification Inventory

| Notification | Handler | Object(s) Affected | State Change |
|---|---|---|---|
| `customer.created` | CustomerCreatedHandler | Lead | Updates existing unconverted Lead with Replicated fields, or inserts a new Lead if none found by email |
| `customer.pending_signup` | TrialSignupHandler | Lead | Inserts a new Lead with `LeadSource = 'Self-Service Trial'` and `Status = 'New'` (skips duplicates by email) |
| `release.asset_downloaded` | AssetDownloadedHandler | Lead, Account, Contact, Opportunity | Converts existing Lead to Account/Contact/Opportunity and enriches Account with Replicated fields; or creates Account + Contact + Opportunity directly if no Lead exists |
| `instance.created` | InstanceEventHandler | Replicated_Instance__c | Upserts instance record with all fields: status, version, cloud provider, k8s distribution, check-in timestamps |
| `instance.upgrade_completed` | InstanceEventHandler | Replicated_Instance__c | Upserts instance record, updating `App_Version__c` and `Last_Check_In__c` |
| `instance.inactive` | InstanceEventHandler | Replicated_Instance__c | Upserts instance record, setting `Status__c = 'Unavailable'` and updating `Last_Check_In__c` |
| `customer.license_expiring` | LicenseExpiringHandler | Task | Inserts a high-priority Task linked to the Account, due 7 days before license expiry, assigned to Account owner |

Note: `customer.pending_signup` and `release.asset_downloaded` are currently coded with display names (`Pending Self-Service Signup`, `Release Assets Downloaded`) — a known naming mismatch that needs fixing.

## Revised Notification Design

The current design conflates Lead conversion with asset download. The revised design separates these concerns: Lead-to-ACO conversion moves to the Enterprise Portal first-user login event, and asset download becomes an activity record with conditional order fulfillment.

### Lifecycle sequence

1. `customer.pending_signup` — Prospect signs up for trial → Create Lead
2. `customer.created` — Customer created in Replicated → Enrich Lead with Replicated fields
3. `customer.ep_user_joined` (`is_first_user == true`) — First user logs into Enterprise Portal → Convert Lead to Account/Contact/Opportunity
4. `release.asset_downloaded` — Customer downloads software → Record download; if `license_type == "paid"`, mark Order as fulfilled

### Revised notification inventory

| Notification | Object(s) Affected | State Change |
|---|---|---|
| `customer.pending_signup` | Lead | Create new Lead (`LeadSource = 'Self-Service Trial'`, `Status = 'New'`) |
| `customer.created` | Lead | Enrich existing Lead with Replicated fields, or create new Lead |
| `customer.ep_user_joined` (`is_first_user == true`) | Lead, Account, Contact, Opportunity | Convert Lead to Account/Contact/Opportunity (or create ACO directly if no Lead) |
| `release.asset_downloaded` | Replicated_Download__c, Order | Record download activity on Account; if `license_type == "paid"`, set `FulfilledAt__c` on the unfulfilled Order |
| `instance.created` | Replicated_Instance__c | Upsert instance with all fields |
| `instance.upgrade_completed` | Replicated_Instance__c | Update `App_Version__c` and `Last_Check_In__c` |
| `instance.inactive` | Replicated_Instance__c | Set `Status__c = 'Unavailable'`, update `Last_Check_In__c` |
| `customer.license_expiring` | Task | Create high-priority Task on Account, due 7 days before expiry |

### Key design decisions

**Lead conversion moves to `customer.ep_user_joined`**: A customer cannot download assets until they've connected to Enterprise Portal, so EP first-user login is the earliest reliable signal that the prospect is actively engaged. This replaces `release.asset_downloaded` as the conversion trigger.

**Download tracking via custom object**: `Replicated_Download__c` (new) records each download as a Related List on the Account, following the same pattern as `Replicated_Instance__c`. Fields: Account lookup, asset type, asset name, asset version, channel, download timestamp. A custom object is preferred over Task because downloads are not to-dos, and Tasks auto-archive after 365 days.

**Order fulfillment on paid download**: When `release.asset_downloaded` arrives with `license_type == "paid"`, look up the Account via `customer_id` → `Replicated_Customer_Id__c`, find the Order with a `LicenseId__c` and no `FulfilledAt__c`, and set `FulfilledAt__c` to the `downloaded_at` timestamp. This closes the loop: Order activation created the license (outbound), paid download confirms the customer pulled the software (inbound).

**`is_first_customer_pull` is not useful for fulfillment**: The vandoor PR (replicatedhq/vandoor#9206) confirmed this flag is write-once per customer — it tracks the first pull ever, not the first pull after license type change. A trial customer's first download sets it, so the first paid download after conversion shows `is_first_customer_pull = false`. The payload's `license_type` field combined with Order state (`FulfilledAt__c IS NULL`) is the correct fulfillment signal.

## Detailed Findings

### Webhook Reception and Routing

Webhooks arrive at the `ReplicatedWebhookReceiver` REST endpoint (`/services/apexrest/replicated/webhook`), which validates the HMAC-SHA256 signature, parses the JSON payload, and publishes a `Replicated_Webhook__e` Platform Event. The `ReplicatedWebhookSubscriber` trigger routes each event by `Event_Type__c` to the appropriate Queueable handler.

### customer.created

Fires when a new customer is created in Replicated. The handler queries for unconverted Leads by email. If a match exists, it enriches the Lead with `Replicated_Customer_Id__c`, `Replicated_License_Type__c`, `Replicated_Channel__c`, and `Replicated_License_Expiry__c`. If no match, it creates a new Lead with those fields plus `LastName`, `Company`, `Email`, `LeadSource`, and `Status`.

### customer.pending_signup

Fires when a prospect submits a self-service trial signup form. Creates a new Lead with `LeadSource = 'Self-Service Trial'` and `Status = 'New'`. Performs a bulk duplicate check by email first and skips any emails already in the system.

### release.asset_downloaded

Fires when a customer downloads release assets. Currently performs Lead-to-ACO conversion (to be replaced — see revised design above). The `release.asset_downloaded` payload includes `license_type` (`"paid"`, `"trial"`, `"dev"`, `"community"`) and `is_first_customer_pull` (boolean, write-once per customer lifetime). It does not include a license ID, but the Order can be reached through Account → Order (via `Replicated_Customer_Id__c` and `LicenseId__c`).

### customer.ep_user_joined

Not currently handled. Fires when a user joins the Enterprise Portal. Payload includes `is_first_user` (boolean), `joined_email`, `access_method` (`"invite"`, `"self_signup"`, `"saml_jit"`), `customer_id`, `customer_name`, and `license_type`. When `is_first_user == true`, this is the conversion trigger for Lead → Account/Contact/Opportunity.

### Instance Events (created, upgrade_completed, inactive)

All three instance events route to `InstanceEventHandler`, which upserts `Replicated_Instance__c` records using `Instance_Id__c` as the external ID. The handler merges multiple events for the same instance in a single batch. Field population varies by event type:

- **instance.created**: Sets all fields (status, version, cloud provider, k8s distribution, first/last check-in, name)
- **instance.upgrade_completed**: Updates `App_Version__c` and `Last_Check_In__c` only
- **instance.inactive**: Sets `Status__c = 'Unavailable'` and updates `Last_Check_In__c`

### customer.license_expiring

Fires when a customer's license is approaching expiration. Creates a high-priority Task linked to the Account (`WhatId`), owned by the Account owner, with a subject of "Trial license expiring for [customer name]" and an activity date 7 days before expiry (or today if already past).

### Sync Loop Prevention

All handlers add modified record IDs to `SyncGuard.inboundSyncIds` to prevent outbound triggers from firing back to Replicated in response to inbound webhook changes.

## Code References

- `create-license/main/default/classes/ReplicatedWebhookReceiver.cls` — REST endpoint, HMAC validation, event publishing
- `create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger` — Event type routing switch
- `create-license/main/default/classes/CustomerCreatedHandler.cls` — Lead create/update on customer.created
- `create-license/main/default/classes/TrialSignupHandler.cls` — Lead creation on self-service signup
- `create-license/main/default/classes/AssetDownloadedHandler.cls` — Lead conversion and Account/Contact/Opportunity creation (to be revised)
- `create-license/main/default/classes/InstanceEventHandler.cls` — Instance record upsert
- `create-license/main/default/classes/LicenseExpiringHandler.cls` — Task creation for expiring licenses
- `create-license/main/default/classes/SyncGuard.cls` — Bidirectional sync loop prevention

## Vandoor Source References

- `replicatedhq/vandoor#9206` — PR that added `is_first_customer_pull` to `release.asset_downloaded` (merged 2026-03-18)
- `pkg/kots/customer/first_software_pull.go` — Write-once `SetFirstSoftwarePulledIfNotSet` using `WHERE first_software_pulled_at IS NULL`
- `pkg/notifications/events/asset_downloaded.go` — `AssetDownloadedEvent` struct with `IsFirstCustomerPull` field and `pullType` notification filter
- EP event structs: `pkg/notifications/events/customer_ep_user_joined.go` — payload includes `is_first_user`, `joined_email`, `access_method`
