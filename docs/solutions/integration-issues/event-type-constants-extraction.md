---
title: "Extract scattered event type string literals into ReplicatedEventType constants class"
category: integration-issues
date: 2026-03-19
tags:
  - apex
  - constants
  - event-routing
  - replicated-integration
  - webhook
  - code-consistency
components:
  - create-license/main/default/classes/ReplicatedEventType.cls
  - create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger
  - create-license/main/default/classes/InstanceEventHandler.cls
  - create-license/main/default/classes/InstanceEventHandlerTest.cls
  - create-license/main/default/classes/TrialSignupHandlerTest.cls
  - create-license/main/default/classes/AssetDownloadedHandlerTest.cls
  - create-license/main/default/classes/CustomerCreatedHandlerTest.cls
  - create-license/main/default/classes/LicenseExpiringHandlerTest.cls
  - create-license/main/default/classes/ReplicatedWebhookReceiverTest.cls
severity: medium
time_to_resolve: 30 minutes
related_pr:
  - 77
related_issues:
  - "#73"
  - "#45"
  - "#67"
---

# Extract scattered event type string literals into ReplicatedEventType constants class

## Problem

Replicated webhook event type strings were scattered as raw string literals across 8+ Apex files (trigger, handlers, test classes). This caused the same bug class to occur twice:

- **PR #67** fixed 4 event types using wrong formats (e.g., `'instance.upgraded'` instead of `'instance.upgrade_completed'`)
- **PR #77** fixed 2 more that used display names (`'Pending Self-Service Signup'`, `'Release Assets Downloaded'`) instead of canonical API keys (`'customer.pending_signup'`, `'release.asset_downloaded'`)

Events matching no `switch` case silently fell through to `when else` and were discarded with a debug log — no error, no alert.

## Root Cause

No single source of truth existed for event type strings. Each handler, test class, and the trigger independently hardcoded the strings as raw literals. The canonical keys come from Replicated's Go source (`replicatedhq/vandoor` repo, `Key()` methods), but developers had to manually look them up and copy them to every location — creating opportunities for typos, inconsistencies, and display-name vs API-key confusion.

## Solution

Created a `ReplicatedEventType` constants class as the single source of truth:

```apex
public class ReplicatedEventType {
    public static final String INSTANCE_CREATED = 'instance.created';
    public static final String INSTANCE_UPGRADE_COMPLETED = 'instance.upgrade_completed';
    public static final String INSTANCE_INACTIVE = 'instance.inactive';
    public static final String CUSTOMER_CREATED = 'customer.created';
    public static final String CUSTOMER_LICENSE_EXPIRING = 'customer.license_expiring';
    public static final String CUSTOMER_PENDING_SIGNUP = 'customer.pending_signup';
    public static final String RELEASE_ASSET_DOWNLOADED = 'release.asset_downloaded';
}
```

Updated all handler classes and test classes to reference constants instead of string literals:

```apex
// InstanceEventHandler.cls — before:
if (event.Event_Type__c == 'instance.created') {

// After:
if (event.Event_Type__c == ReplicatedEventType.INSTANCE_CREATED) {
```

```apex
// Test classes — before:
Event_Type__c = 'customer.pending_signup'

// After:
Event_Type__c = ReplicatedEventType.CUSTOMER_PENDING_SIGNUP
```

Added a comment to the trigger referencing the constants class, since Apex `switch on` requires compile-time string literals in `when` clauses — the trigger cannot use constants directly.

### Apex `switch on` constraint

Apex `switch on` statements only accept string literals in `when` clauses — not variables or constants. This is a compile-time requirement. The trigger must keep raw string literals:

```apex
// Canonical keys defined in ReplicatedEventType.cls (switch on requires literals).
switch on event.Event_Type__c {
    when 'instance.created', 'instance.upgrade_completed', 'instance.inactive' {
```

The safety net: if a trigger `when` clause has a typo, tests fail because they construct events using the correct constant values and the handler never receives the misrouted events.

## Prevention

### Adding new event types checklist

```markdown
- [ ] Found canonical key in replicatedhq/vandoor pkg/notifications/events/
- [ ] Copied string verbatim (did not infer or retype from display name)
- [ ] Added constant to ReplicatedEventType.cls
- [ ] Added row to canonical reference table in webhook-event-type-naming-mismatch.md
- [ ] Added event type to hack/setup-webhook-subscription
- [ ] Added when clause to ReplicatedWebhookSubscriber.trigger (exact string from constant)
- [ ] Created handler class using ReplicatedEventType.CONSTANT_NAME
- [ ] Created test class using ReplicatedEventType.CONSTANT_NAME for Event_Type__c and payload
- [ ] Ran full test suite — all passing
- [ ] Verified string consistency across all locations with case-sensitive search
```

### Verification chain

The architecture has five links from incoming webhook to Salesforce record:

| Link | File | What to verify |
|------|------|----------------|
| 1. Subscription | `hack/setup-webhook-subscription` | Event type string matches constant value |
| 2. Receiver | `ReplicatedWebhookReceiver.cls` | Passes `event` field through verbatim to `Event_Type__c` |
| 3. Trigger | `ReplicatedWebhookSubscriber.trigger` | `when` clause string matches constant value exactly |
| 4. Handler | `*Handler.cls` | Uses `ReplicatedEventType.CONSTANT` (not string literal) |
| 5. Tests | `*Test.cls` | Uses `ReplicatedEventType.CONSTANT` for both `Event_Type__c` and payload |

### How tests catch trigger typos

```
Test buildEvent(ReplicatedEventType.CONSTANT, payload)
  → Trigger switch on event.Event_Type__c
    → If 'when' matches constant value → handler enqueued → test passes
    → If 'when' has typo → routes to 'when else' → handler skipped → test fails
```

After this change, string literals only exist in two places: the constants class (single source of truth) and the trigger's `when` clauses (language constraint). A grep for direct string comparisons in handler classes should return zero results:

```bash
grep -rn "Event_Type__c == '" create-license/main/default/classes/
# Should return 0 results — all comparisons use constants
```

## Cross-References

- [Webhook event type naming mismatch](webhook-event-type-naming-mismatch.md) — Documents both rounds of naming fixes and the canonical event type reference table
- [Trial handler bulkification](trial-handler-bulkification-governor-limit.md) — Introduced the trial lifecycle handlers where display-name mismatches originated
- [Webhook receiver HMAC verification](webhook-receiver-hmac-verification.md) — Platform Event and subscriber trigger architecture
- [Wrong identifier type in API call](wrong-identifier-type-in-api-call.md) — Similar API field semantic mismatch pattern
- [Salesforce data model review](salesforce-data-model-review-hardening.md) — `Event_Type__c` field design on `Replicated_Webhook__e`
- [Bidirectional sync loop prevention](bidirectional-sync-loop-prevention.md) — SyncGuard pattern used by all event handlers
- [jq response shape mismatch](../build-errors/jq-response-shape-mismatch-silent-makefile-target.md) — Prevention checklist noting string constants should not be duplicated across files
- PR #67: First round of event type naming fixes
- PR #77: Second round of naming fixes + constants extraction
- PR #50: Trial lifecycle handlers (introduced the display-name cases)
- PR #51: Instance and license event handlers (established the batched handler pattern)
