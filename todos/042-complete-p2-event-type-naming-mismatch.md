---
status: complete
priority: p2
issue_id: "042"
tags:
  - code-review
  - integration
  - webhook
dependencies: []
---

# Verify event type naming between subscription and trigger

## Problem Statement

The webhook subscription script registers event types using API identifier format (e.g., `instance.upgrade_completed`, `customer.license_expiring`), but the `ReplicatedWebhookSubscriber` trigger routes events using different string formats (e.g., `instance.upgraded`, `customer.license.expiring`, `Pending Self-Service Signup`). If the Replicated webhook payload uses the API identifier format, several handlers will never fire because the trigger's `switch on` cases won't match.

## Findings

**Subscription script** (`hack/setup-webhook-subscription:30-38`) registers:

| Subscription Event Type | Trigger `switch on` Case | Match? |
|---|---|---|
| `customer.created` | `'customer.created'` | YES |
| `customer.updated` | (none) | No handler |
| `customer.license_expiring` | `'customer.license.expiring'` | MISMATCH (underscore vs dot) |
| `customer.pending_self_service_signup` | `'Pending Self-Service Signup'` | MISMATCH (display name format) |
| `release.assets_downloaded` | `'Release Assets Downloaded'` | MISMATCH (display name format) |
| `instance.created` | `'instance.created'` | YES |
| `instance.upgrade_completed` | `'instance.upgraded'` | MISMATCH (different verb form) |
| `instance.inactive` | `'instance.inactive'` | YES |

**Trigger file:** `create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger:17-32`

The actual format depends on what `ReplicatedWebhookReceiver` sets in `Event_Type__c` when processing inbound webhooks. This needs verification against actual Replicated webhook payloads or the [Replicated Vendor API v3 spec](https://api.replicated.com/vendor/v3/spec/vendor-api-v3.json).

## Proposed Solutions

### Option A: Verify against actual webhook payloads (Recommended)
- Send a test webhook and inspect the payload's event type field
- Update whichever side (script or trigger) has the wrong format
- **Effort**: Small
- **Risk**: None

### Option B: Check Replicated API documentation
- Review the notification subscription API docs for event type format
- Cross-reference with webhook payload docs
- **Effort**: Small
- **Risk**: Low — docs may be incomplete

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Verified the exact event type strings in actual Replicated webhook payloads
- [ ] Subscription event types and trigger `switch on` cases use the same format
- [ ] All 4 mismatched event types are reconciled

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #67 code review — trigger pre-dates this PR but subscription must agree with it | The trigger uses a mix of API format and display-name format for different events |

## Resources

- PR: https://github.com/crdant/replicated-salesforce-fulfillment/pull/67
- Subscription script: `hack/setup-webhook-subscription`
- Trigger: `create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger`
- Replicated API spec: `https://api.replicated.com/vendor/v3/spec/vendor-api-v3.json`
- Past solution: `docs/solutions/integration-issues/wrong-identifier-type-in-api-call.md`
