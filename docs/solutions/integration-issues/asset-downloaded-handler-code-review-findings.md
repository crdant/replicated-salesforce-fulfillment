---
title: Code Review Findings — AssetDownloadedHandler Rewrite
category: integration-issues
date: 2026-03-19
severity: moderate
tags:
  - code-review
  - security
  - reliability
  - code-quality
  - webhook-handlers
  - apex
related_issues:
  - "#92"
  - "#93"
  - "#94"
  - "#95"
components:
  - AssetDownloadedHandler.cls
  - AssetDownloadedHandlerTest.cls
---

# Code Review Findings — AssetDownloadedHandler Rewrite (PR #92)

## Problem

A multi-agent code review of the `AssetDownloadedHandler` rewrite (PR #92) surfaced five findings. Two were handler-specific and fixed in-PR. Three were cross-cutting concerns spanning multiple handlers, deferred to dedicated sweep PRs to avoid creating inconsistency by fixing one handler but not its siblings.

This is the third webhook handler review to flag the same recurring patterns (payload values in logs, all-or-nothing DML, duplicated utilities), indicating these are systemic issues rather than one-off mistakes.

## Root Cause

Each webhook handler is implemented independently, copying patterns from existing handlers. When the copied pattern contains a policy violation or suboptimal practice, it propagates to every subsequent handler. No shared utilities or architectural enforcement prevents the duplication.

Specifically:
1. **Payload logging** — `System.debug()` statements are written ad-hoc per handler with no centralized logging discipline. Each handler independently decides what to include.
2. **DML semantics** — Bare `insert`/`update` is simpler to write than `Database.insert(records, false)` with error handling. New handlers copy the simpler pattern.
3. **Utility duplication** — `parseDateTime` exists in two handlers with different fallback behavior. `parseDate` is duplicated across three. No shared utility enforces consistency.

## Solution

### Fixed In-PR

**1. Customer ID stripped from debug log (todo 067)**

```apex
// Before
System.debug(LoggingLevel.WARN,
    'AssetDownloadedHandler: no Account found for customer_id ' + customerId + ', skipping');

// After
System.debug(LoggingLevel.WARN,
    'AssetDownloadedHandler: no Account found for customer_id, skipping');
```

Institutional policy (documented in `webhook-receiver-code-review-findings.md` and the `ReplicatedWebhookSubscriber` trigger comment) prohibits logging payload-derived values. This is the same issue fixed in todo 029 (other handlers) and todo 060 (CustomerUpdatedHandler).

**2. Paid-event filter consolidated (todo 068)**

```apex
// Before — split filtering across two methods
// In execute():
String licenseType = (String) data.get('license_type');
if (licenseType == 'paid') {
    paidEvents.add(data);
    paidAccountIds.add(acc.Id);
    String appId = (String) data.get('app_id');
    if (String.isNotBlank(appId)) {
        paidAppIds.add(appId);
    }
}
// In fulfillOrders():
String appId = (String) data.get('app_id');
if (String.isBlank(appId)) {
    continue;
}

// After — single filter point
String licenseType = (String) data.get('license_type');
String appId = (String) data.get('app_id');
if (licenseType == 'paid' && String.isNotBlank(appId)) {
    paidEvents.add(data);
    paidAccountIds.add(acc.Id);
    paidAppIds.add(appId);
}
// fulfillOrders guard removed — all events guaranteed valid
```

A paid event with blank `app_id` would traverse `fulfillOrders` (including two SOQL queries) before being discarded. Consolidating the filter at the source eliminates the dead code path.

### Deferred to GitHub Issues

**3. `parseDateTime` silent fallback (GitHub #93, todo 065)**

`AssetDownloadedHandler.parseDateTime` returns `DateTime.now()` on bad input with no logging. `InstanceEventHandler.parseDateTime` returns `null` and logs a warning. The inconsistency should be resolved when `parseDateTime` is extracted to a shared utility (todo 064).

**4. All-or-nothing DML (GitHub #94, todo 066)**

Bare `insert downloads` and `update toUpdate` mean one bad record kills the entire batch. The same pattern exists in `CustomerUpdatedHandler` (todo 061) and other handlers. Should be fixed as a sweep using `Database.insert(records, false)` with WARN-level failure logging.

**5. Missing test for bad-timestamp path (GitHub #95, todo 069)**

The `parseDateTime` catch block is never tested with a well-formed payload containing an unparseable `downloaded_at` value. Depends on the fallback decision in #93.

## Triage Decision: Do vs. Defer

The review split findings by scope:

| Criteria | Do Now | Defer |
|----------|--------|-------|
| Scope | Handler-specific | Spans multiple handlers |
| Fix creates inconsistency? | No | Yes — fixing one handler leaves others wrong |
| Risk of deferral | Low — institutional policy clear | Low — existing behavior is functional |
| Examples | Log leak, split filter | DML semantics, parseDateTime, test gap |

The principle: fixing a cross-cutting concern in one handler while leaving it unfixed in siblings creates a new kind of inconsistency. Better to sweep all handlers in a single chore PR.

## Recurring Patterns Across Handler Reviews

| Pattern | Occurrences | First Found | Todos |
|---------|-------------|-------------|-------|
| Payload values in debug logs | 3 handlers | Todo 029 | 029, 060, 067 |
| All-or-nothing DML | 2+ handlers | Todo 061 | 061, 066 |
| Duplicated parseDate/parseDateTime | 4+ handlers | Todo 064 | 064, 065 |

## Prevention: New Handler Checklist

When implementing or reviewing a webhook handler, verify:

- [ ] `System.debug()` calls contain no payload-derived values (customer IDs, emails, field values)
- [ ] DML uses `Database.insert(records, false)` / `Database.update(records, false)` with failure logging
- [ ] Date/time parsing uses shared utility (`WebhookPayloadUtils`) or documents why it diverges
- [ ] SyncGuard applied to records with outbound triggers, skipped for records without
- [ ] All filter conditions applied at collection time, not split across methods
- [ ] Tests cover: happy path, missing record, malformed payload, bulk (200+), partial DML failure

## Cross-References

- [PR #92](https://github.com/crdant/replicated-salesforce-fulfillment/pull/92) — Source PR
- [GitHub #93](https://github.com/crdant/replicated-salesforce-fulfillment/issues/93) — parseDateTime fallback
- [GitHub #94](https://github.com/crdant/replicated-salesforce-fulfillment/issues/94) — Partial-success DML sweep
- [GitHub #95](https://github.com/crdant/replicated-salesforce-fulfillment/issues/95) — Bad-timestamp test
- `asset-downloaded-handler-lifecycle-decomposition.md` — Design decisions for the rewrite
- `hardening-customer-updated-handler.md` — Same patterns fixed in CustomerUpdatedHandler
- `webhook-receiver-code-review-findings.md` — Institutional logging policy
- `bidirectional-sync-loop-prevention.md` — SyncGuard pattern reference
- `trial-handler-bulkification-governor-limit.md` — Bulkification checklist
