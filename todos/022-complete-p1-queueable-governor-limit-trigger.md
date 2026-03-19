---
status: complete
priority: p1
issue_id: "022"
tags:
  - code-review
  - performance
  - governor-limits
  - platform-events
dependencies: []
---

# Trigger enqueues one Queueable per event — will hit 50-job governor limit

## Problem Statement

The `ReplicatedWebhookSubscriber` trigger calls `System.enqueueJob()` inside a `for` loop over `Trigger.New`. Platform Event triggers can receive up to 2,000 events per batch. Salesforce enforces a limit of 50 `System.enqueueJob()` calls per transaction. If more than 50 events arrive in one trigger execution, the trigger throws `System.LimitException`, the `setResumeCheckpoint()` call never executes, and the Platform Event subscription retries the same batch indefinitely — creating a stuck subscription.

Before this PR, the trigger had no actual enqueue calls (only a `when else` debug branch), so this limit was never reachable. This PR introduces the first real enqueue calls, making the governor limit exploitable.

This finding was identified by 3 agents: performance-oracle, architecture-strategist, and the main review synthesis.

## Findings

- **Performance Oracle**: At 50+ events per batch, the trigger fails. At 200+ events (realistic for a marketing campaign burst), the failure is severe. After bulkification, the same code handles 2,000 events within governor limits.
- **Architecture Strategist**: The fix requires both trigger refactoring (batch by event type) AND handler bulkification (accept `List<String>` instead of `String`). These are coupled changes.
- **Learnings Researcher**: The project documentation in `webhook-receiver-hmac-verification.md` warns against adding heavy processing to the subscriber trigger directly.

## Proposed Solutions

### Option A: Batch payloads by event type in trigger + bulkify handlers (Recommended)
- Collect payloads into lists by event type, enqueue at most 3 Queueables (one per type)
- Refactor each handler to accept `List<String>` and process in bulk with set-based SOQL and list-based DML
- **Pros**: Stays within governor limits at any scale; improves SOQL/DML efficiency
- **Cons**: Significant refactor of all 3 handlers + trigger + tests
- **Effort**: Large
- **Risk**: Low — behavior is identical, just batched

### Option B: Add a guard check in the trigger loop
- Track enqueue count and stop enqueuing after 50, letting remaining events replay via checkpoint
- **Pros**: Minimal code change
- **Cons**: Drops events on the floor until replay; doesn't address underlying scalability; handler SOQL/DML limits still apply within each job
- **Effort**: Small
- **Risk**: Medium — relies on Platform Event retry semantics being correct

### Option C: Accept current limit with documentation
- Add a code comment acknowledging the 50-job limit
- File a follow-up issue for bulkification
- **Pros**: No code change needed now
- **Cons**: Production failure if >50 events arrive in one batch; stuck subscription risk
- **Effort**: None
- **Risk**: High for production traffic

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `create-license/main/default/triggers/ReplicatedWebhookSubscriber.trigger`, all 3 handler classes, all 3 test classes
- **Components**: Platform Event trigger, Queueable handlers
- **Governor limits**: 50 `System.enqueueJob()` per transaction; 100 SOQL queries; 150 DML statements

## Acceptance Criteria

- [ ] Trigger enqueues at most 3 Queueable jobs regardless of batch size
- [ ] Each handler processes multiple payloads in a single execution
- [ ] SOQL queries use `IN :collection` for bulk lookups
- [ ] DML uses list-based insert/update
- [ ] Tests verify batch processing with multiple payloads

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | 3 agents flagged this; coupled with handler bulkification |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
- [Salesforce Governor Limits](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm)
- [Platform Event Allocation](https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_event_limits.htm)
