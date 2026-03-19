---
title: "Webhook event type naming mismatch between Replicated API and Salesforce integration"
category: integration-issues
date: 2026-03-19
tags:
  - webhook
  - event-type
  - replicated-api
  - salesforce-apex
  - naming-convention
severity: high
components:
  - hack/setup-webhook-subscription
  - create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger
  - create-license/main/default/classes/InstanceEventHandler.cls
  - create-license/main/default/classes/InstanceEventHandlerTest.cls
  - create-license/main/default/classes/LicenseExpiringHandlerTest.cls
related_issues:
  - "#45"
  - "#67"
  - "#12"
---

# Webhook event type naming mismatch between Replicated API and Salesforce integration

## Problem

The webhook subscription script and Salesforce trigger used incorrect event type strings that did not match the Replicated platform's canonical identifiers. Two incorrect names in the subscription script would cause the Replicated API to reject the event configs. Two incorrect names in the trigger would cause incoming webhook events to be silently dropped (routed to `when else` and logged as unhandled).

**Symptoms:**
- Subscription creation fails for `customer.pending_self_service_signup` and `release.assets_downloaded` (API rejects unknown event types)
- `instance.upgrade_completed` events arrive but match no trigger case (trigger expects `instance.upgraded`)
- `customer.license_expiring` events arrive but match no trigger case (trigger expects `customer.license.expiring`)

## Root Cause

Event type strings were guessed or derived from display names instead of verified against the canonical source. The trigger used a mix of formats: correct API identifiers (`instance.created`), close-but-wrong variants (`instance.upgraded` instead of `instance.upgrade_completed`), and dot-separated names (`customer.license.expiring` instead of `customer.license_expiring`). The subscription script used inflated names (`customer.pending_self_service_signup` instead of `customer.pending_signup`) and wrong pluralization (`release.assets_downloaded` instead of `release.asset_downloaded`).

The Replicated platform defines canonical event type keys in Go structs within `replicatedhq/vandoor` at `pkg/notifications/events/`. Each event struct implements a `Key()` method returning the exact string used in both the subscription API and webhook payloads. There is no mapping layer — subscription identifiers and payload `event` strings are identical.

## Solution

### Four corrections across 6 files

**Subscription script** (`hack/setup-webhook-subscription`):

```bash
# BEFORE (wrong):
{ eventType: "customer.pending_self_service_signup", filters: {} },
{ eventType: "release.assets_downloaded",            filters: {} },

# AFTER (correct):
{ eventType: "customer.pending_signup",              filters: {} },
{ eventType: "release.asset_downloaded",             filters: {} },
```

**Trigger** (`ReplicatedWebhookSubscriber.trigger`):

```apex
// BEFORE (wrong):
when 'instance.created', 'instance.upgraded', 'instance.inactive' {
when 'customer.license.expiring' {

// AFTER (correct):
when 'instance.created', 'instance.upgrade_completed', 'instance.inactive' {
when 'customer.license_expiring' {
```

**Handler** (`InstanceEventHandler.cls`):

```apex
// BEFORE:
} else if (event.Event_Type__c == 'instance.upgraded') {
// AFTER:
} else if (event.Event_Type__c == 'instance.upgrade_completed') {
```

**Tests** (`InstanceEventHandlerTest.cls`, `LicenseExpiringHandlerTest.cls`): All event type string references updated to match.

## Investigation Steps

1. Code review of PR #67 compared subscription event types against trigger switch-on cases — noticed 4 of 8 had format discrepancies
2. Verified trigger file existed on the branch (pre-dates the subscription script)
3. Researched `replicatedhq/vandoor` GitHub repository for canonical event type definitions
4. Found events defined in `pkg/notifications/events/` as Go structs with `Key()` methods
5. Confirmed webhook payload `event` field uses `Key()` string directly (no transformation)
6. Identified 2 errors in subscription script and 2 errors in trigger + handler

## Canonical Event Type Reference

Source: `replicatedhq/vandoor` `pkg/notifications/events/event.go` `GetAllEvents()`

| Event Key | Display Name | Category |
|---|---|---|
| `instance.created` | Instance Created | Instance |
| `instance.ready` | Instance Ready | Instance |
| `instance.upgrade_started` | Instance Upgrade Started | Instance |
| `instance.upgrade_completed` | Instance Upgrade Completed | Instance |
| `instance.version_behind` | Instance Version Behind | Instance |
| `instance.inactive` | Instance Inactive | Instance |
| `release.created` | Release Created | Release |
| `release.promoted` | Release Promoted | Release |
| `release.asset_downloaded` | Release Asset Downloaded | Release |
| `customer.created` | Customer Created | Customer |
| `customer.updated` | Customer Updated | Customer |
| `customer.archived` | Customer Archived | Customer |
| `customer.unarchived` | Customer Unarchived | Customer |
| `customer.license_expiring` | Customer License Expiring | Customer |
| `customer.pending_signup` | Pending Self-Service Signup | Customer |
| `customer.ep_invite_sent` | EP Invite Sent | Customer |
| `customer.ep_access_granted` | EP Access Granted | Customer |
| `customer.ep_user_joined` | EP User Joined | Customer |
| `support.bundle.uploaded` | Support Bundle Uploaded | Support |
| `support.bundle.analyzed` | Support Bundle Analyzed | Support |

## Naming Patterns

| Pattern | Example | Rule |
|---|---|---|
| Separators | `customer.license_expiring` | Dot between category and event, underscore within compound words |
| Tense | `upgrade_completed`, `asset_downloaded` | Past participle (`verb_completed`/`verb_downloaded`), not simple past (`upgraded`) |
| Pluralization | `asset_downloaded` | Singular per-event, not plural (`assets_downloaded`) |
| Category prefix | `customer.*`, `instance.*` | Lowercase category, always present |

## Prevention

### Before adding a new event type

1. **Find the canonical key**: Search `replicatedhq/vandoor` `pkg/notifications/events/` for the Go struct and its `Key()` return value
2. **Copy-paste the string**: Do not retype, infer from display names, or apply grammar rules
3. **Verify the chain**: Same string must appear in subscription config, trigger `switch on` case, handler conditional, and test fixtures
4. **Test with a negative case**: Verify the handler ignores payloads with similar-but-wrong event type names

### Common mistakes

- Guessing tense: `upgraded` vs `upgrade_completed` — always check `Key()`
- Display name correlation: UI shows "Assets Downloaded" but key is `asset_downloaded` (singular)
- Dot vs underscore: `customer.license.expiring` vs `customer.license_expiring` — dots only separate category from event name
- Expanded names: `pending_self_service_signup` vs `pending_signup` — the key is shorter than you'd expect

## Related Documentation

- [Webhook receiver HMAC verification](webhook-receiver-hmac-verification.md) — Platform Event and subscriber trigger architecture
- [Wrong identifier type in API call](wrong-identifier-type-in-api-call.md) — Similar API field semantic mismatch pattern
- [Salesforce data model review](salesforce-data-model-review-hardening.md) — `Event_Type__c` field design on `Replicated_Webhook__e`
- PR #67: Webhook subscription automation
- PR #51: Instance and license event handlers (introduced the trigger cases)
