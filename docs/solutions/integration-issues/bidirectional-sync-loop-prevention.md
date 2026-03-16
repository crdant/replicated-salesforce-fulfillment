---
title: "Bidirectional Sync Loop Prevention: SyncGuard for Salesforce-Replicated Integration"
category: integration-issues
date: 2026-03-16
tags:
  - salesforce
  - apex
  - replicated
  - bidirectional-sync
  - loop-prevention
  - platform-events
  - webhooks
  - queueable
components:
  - SyncGuard.cls
  - FulfillOrder.trigger
  - ReplicatedFulfillment.cls
  - Replicated_Webhook__e
severity: high
time_to_resolve: 1-2 hours
---

# Bidirectional Sync Loop Prevention with SyncGuard

## Problem

In the bidirectional sync between Salesforce and Replicated, every write creates a potential echo:

1. A Salesforce trigger fires on an Order/Account change and enqueues a Queueable to push data to the Replicated API (outbound).
2. Replicated fires a webhook back to Salesforce (inbound).
3. The inbound webhook handler performs DML on the same Salesforce record.
4. That DML fires the outbound trigger again, enqueuing another callout.
5. The cycle repeats indefinitely.

Without a guard, the symptom is runaway Queueable job chains, repeated callouts to the Replicated API, and eventual governor limit exceptions or webhook auto-disable after consecutive failures. There is no explicit error message -- the symptom is unbounded resource consumption.

## Root Cause

Salesforce's trigger execution model does not distinguish between user-initiated DML and programmatic DML made by an integration handler. Triggers fire regardless of origin. In a bidirectional integration where both systems can mutate shared state and notify each other via webhooks/triggers, this creates an unbounded feedback loop.

## Investigation

Three complementary strategies were identified (documented in `docs/research/2026-03-16-event-driven-bidirectional-sync.md`):

| Strategy | Scope | Durability | Tradeoff |
|----------|-------|-----------|----------|
| **Static Set Guard** (`SyncGuard`) | Within one transaction | Resets per execution context | Zero persistence cost, simple |
| **Integration User Detection** | Cross-transaction (CDC only) | N/A | Requires dedicated integration user, CDC-only |
| **`Last_Synced_By__c` Durable Field** | Cross-transaction | Persists in database | Extra DML write per inbound sync, must be cleared on user changes |

The decision was to implement Strategy A (SyncGuard) first as the foundation and add Strategy C (`Last_Synced_By__c`) as a follow-on tracked in [issue #7](https://github.com/crdant/replicated-salesforce-fulfillment/issues/7).

## Solution

### The SyncGuard Class

```apex
// Transaction-scoped guard for bidirectional sync loop prevention.
// Static sets reset between execution contexts (Queueable, CDC, Platform Event
// subscribers). Cross-transaction loop prevention requires the Last_Synced_By__c
// durable guard on Account (see #7).
public class SyncGuard {
    // Records currently being updated by inbound webhook processing.
    // Outbound triggers check this set and skip records present here.
    public static Set<Id> inboundSyncIds = new Set<Id>();

    // Records already sent outbound in this transaction.
    // Prevents duplicate outbound callouts for the same record.
    public static Set<Id> outboundSyncIds = new Set<Id>();
}
```

Two static `Set<Id>` fields serve distinct purposes:

- **`inboundSyncIds`**: Breaks the echo loop. Outbound triggers skip records being processed inbound.
- **`outboundSyncIds`**: Prevents duplicate outbound callouts for the same record within a single transaction (handles bulk DML where the same record could trigger multiple enqueue attempts).

### Usage Pattern: Inbound Handler

Mark record IDs **before** performing DML so that triggers firing during the DML see the guard:

```apex
// Inbound handler processing a Replicated webhook event
SyncGuard.inboundSyncIds.add(account.Id);
update account;  // triggers fire here but see the guard
```

For bulk operations, accumulate all IDs first:

```apex
List<Account> toUpdate = new List<Account>();
for (WebhookEvent e : events) {
    Account a = buildAccount(e);
    SyncGuard.inboundSyncIds.add(a.Id);
    toUpdate.add(a);
}
update toUpdate;  // all IDs already guarded
```

### Usage Pattern: Outbound Trigger

Check both sets before enqueuing outbound sync:

```apex
trigger SyncAccountToReplicated on Account (after update) {
    for (Account acct : Trigger.new) {
        if (SyncGuard.inboundSyncIds.contains(acct.Id)) {
            continue;  // came from Replicated, skip outbound
        }
        if (SyncGuard.outboundSyncIds.contains(acct.Id)) {
            continue;  // already queued this transaction
        }
        SyncGuard.outboundSyncIds.add(acct.Id);
        System.enqueueJob(new ReplicatedOutboundSync(acct.Id));
    }
}
```

### Why Static Sets?

Static variables in Apex persist for the lifetime of a single execution context -- from the first statement through all trigger cascades and DML operations within that transaction. They reset automatically when the context ends. This makes them ideal for within-transaction recursion guards: zero persistence cost, no SOQL query, no cleanup step.

## Known Limitation: Transaction Scope

Static sets reset between execution contexts. Each Queueable job, CDC subscriber, and Platform Event trigger subscriber runs in its own execution context with empty sets.

| Scenario | SyncGuard covers it? | Last_Synced_By__c needed? |
|----------|---------------------|--------------------------|
| Inbound handler + outbound trigger in same context | Yes | No |
| Platform Event subscriber + outbound trigger (same context) | Yes | No |
| Inbound Queueable + outbound trigger (different contexts) | No | Yes |
| Cross-transaction loop (scheduled job, new session) | No | Yes |
| Duplicate outbound enqueue in same transaction | Yes (`outboundSyncIds`) | No |

The `Last_Synced_By__c` durable field guard is the cross-transaction complement, tracked in [issue #7](https://github.com/crdant/replicated-salesforce-fulfillment/issues/7).

## Common Pitfalls

**Adding the ID after the DML.** The trigger fires synchronously during the `update` call. If you set the guard after the DML, the trigger has already run against an unguarded record.

**Assuming the guard persists across async boundaries.** A Queueable job starts with empty static sets regardless of what the parent context set. This is correct behavior but can surprise developers who expect the guard to carry over.

**Checking the wrong set.** `inboundSyncIds` suppresses outbound triggers. `outboundSyncIds` prevents duplicate outbound enqueues. Inverting them defeats both purposes.

**Not guarding related-object triggers.** If Account triggers are guarded but related triggers (e.g., on Order or Contact) are not, inbound webhook updates that touch multiple objects can still trigger unguarded outbound sync on the related objects.

**Confusing SyncGuard with idempotency.** SyncGuard prevents echo loops, not duplicate event processing. Idempotency for webhook retries requires a separate deduplication mechanism.

## Prevention

- Draw an explicit execution flow diagram showing every write path (inbound and outbound) before implementing any bidirectional sync.
- Guard every object type that participates in bidirectional sync, not just the primary object.
- Always mark IDs before DML, never after.
- Use Platform Events for inbound decoupling -- the physical separation makes data flow explicit and forces a deliberate handoff point where guard logic applies.
- Plan for the `Last_Synced_By__c` durable guard from the start for any integration that crosses async boundaries.

## Test Scenarios

1. **Inbound guard suppresses outbound**: Add Account ID to `inboundSyncIds`, update Account, assert no outbound job enqueued.
2. **Outbound fires without guard**: Update Account with empty sets, assert outbound job enqueued.
3. **Outbound deduplication**: Two code paths try to enqueue for the same ID; assert only one job created.
4. **Async boundary reset**: Verify `inboundSyncIds` is empty inside a Queueable that was enqueued from a guarded context.
5. **Bulk guard**: Add 10 IDs to `inboundSyncIds`, bulk update, assert zero outbound jobs.
6. **ID-scoped guard**: Guard Account A, update Account B, assert outbound job fires for B.

## Cross-References

- Research: [`docs/research/2026-03-16-event-driven-bidirectional-sync.md`](../../research/2026-03-16-event-driven-bidirectional-sync.md) -- Loop Prevention Strategies section
- Parent epic: [#6 Event-driven bidirectional sync](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6)
- Implementing issue: [#9 Add SyncGuard for loop prevention](https://github.com/crdant/replicated-salesforce-fulfillment/issues/9) (closed)
- Implementing PR: [#17 Add SyncGuard for loop prevention and configure Salesforce Site](https://github.com/crdant/replicated-salesforce-fulfillment/pull/17) (merged)
- Durable guard: [#7 Define Salesforce data model for Replicated event sync](https://github.com/crdant/replicated-salesforce-fulfillment/issues/7) (`Last_Synced_By__c`)
- Primary consumer: [#10 Implement webhook receiver with HMAC signature verification](https://github.com/crdant/replicated-salesforce-fulfillment/issues/10)
- Instance handlers: [#12 Implement instance and license event handlers](https://github.com/crdant/replicated-salesforce-fulfillment/issues/12)
