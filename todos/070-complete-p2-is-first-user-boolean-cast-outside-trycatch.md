---
status: complete
priority: p2
issue_id: "070"
tags:
  - code-review
  - reliability
  - apex
  - error-handling
dependencies: []
---

# `is_first_user` boolean cast outside try/catch can terminate entire batch

## Problem Statement

The `is_first_user` field access at line 33 of `EpUserJoinedHandler.cls` casts to `Boolean` outside the try/catch block (lines 18-24). If the Replicated API sends this field as a String (`"true"`) instead of a JSON boolean (`true`), the cast throws `System.TypeException`. This unhandled exception terminates processing of ALL remaining events in the batch — not just the malformed one.

Every other handler in this project wraps all payload access inside try/catch. This field uniquely falls outside that protection because it's accessed after the try/catch block.

## Findings

- **Architecture Strategist**: Flagged as the one item to fix before merge. The `JSON.deserializeUntyped()` method preserves JSON booleans as Apex `Boolean` objects for well-formed payloads, but if the API changes, the entire batch silently fails.
- **Security Sentinel**: Noted the test gap — no test verifies behavior when `is_first_user` is a non-boolean type.
- **Learnings Researcher**: Established hardening pattern (todo #024) requires defensive casting on all payload field access.

## Proposed Solutions

### Option A: Move inside try/catch (Recommended)

Move the `is_first_user` check inside the existing try/catch block so a malformed value skips the single event rather than crashing the batch.

```apex
for (Replicated_Webhook__e event : this.events) {
    Map<String, Object> data;
    try {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
        data = (Map<String, Object>) parsed.get('data');
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: malformed payload, skipping');
        continue;
    }

    if (data == null) {
        System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: missing data in payload');
        continue;
    }

    // Only process first-user events — inside try scope for defensive casting.
    Object isFirstUser = data.get('is_first_user');
    if (!(isFirstUser instanceof Boolean) || !(Boolean) isFirstUser) {
        continue;
    }
    // ... rest of event processing
}
```

- Pros: Minimal change, matches defensive pattern used in other handlers
- Cons: None
- Effort: Small
- Risk: None

### Option B: Wrap with instanceof check

```apex
Boolean isFirst = data.get('is_first_user') instanceof Boolean
    ? (Boolean) data.get('is_first_user')
    : false;
if (!isFirst) { continue; }
```

- Pros: Explicit type safety without changing try/catch scope
- Cons: Slightly more verbose
- Effort: Small
- Risk: None

## Recommended Action

Option A — simplest, most consistent with existing patterns.

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandler.cls` line 32-35
- **Affected components**: Webhook event processing pipeline
- **Database changes**: None

## Acceptance Criteria

- [ ] `is_first_user` type mismatch skips the single event, does not crash the batch
- [ ] Existing tests continue to pass
- [ ] Add test: event with `is_first_user` as String `"true"` is gracefully skipped

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — architecture strategist + security sentinel |

## Resources

- PR: #91
- File: `EpUserJoinedHandler.cls` lines 32-35
- Related: todo #024 (payload validation pattern)
