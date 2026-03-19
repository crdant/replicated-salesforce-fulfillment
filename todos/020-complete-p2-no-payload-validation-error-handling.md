---
status: complete
priority: p2
issue_id: "020"
tags:
  - code-review
  - security
  - error-handling
  - resilience
dependencies: []
---

# No payload validation or error handling in handlers

## Problem Statement

All three handlers perform `JSON.deserializeUntyped(this.payload)` and immediately cast the `data` key without null checks or try-catch blocks. Malformed payloads, missing `data` keys, or unexpected types crash the handler with unhandled exceptions. Additionally, `CustomerCreatedHandler` calls `Date.valueOf(expiresAt.substring(0, 10))` which can throw `StringException` on short strings or `TypeException` on invalid date formats.

The project's `Payload__c` field on Platform Events cannot be marked required (LongTextArea limitation documented in `salesforce-longtextarea-required-platform-event.md`), so null payloads are possible even though the receiver validates upstream.

This finding was identified by 2 agents: security-sentinel and learnings-researcher (citing existing documentation).

## Findings

- **Security Sentinel**: Finding #2 (MEDIUM) — malformed payloads crash handlers; retry storms consume governor limits
- **Security Sentinel**: Finding #6 (LOW) — `Date.valueOf()` on malformed `expires_at` throws unhandled exception
- **Learnings Researcher**: `salesforce-longtextarea-required-platform-event.md` says "Always add a defensive null check for `Payload__c`"
- **Architecture Strategist**: "None of the three handlers wrap their DML operations in try-catch blocks. An unhandled exception will cause the Queueable job to fail."

## Proposed Solutions

### Option A: Add defensive validation and try-catch (Recommended)
- Check `String.isBlank(this.payload)` at start of each handler
- Wrap JSON deserialization in try-catch
- Validate `data` key exists and is a Map before casting
- Wrap `Date.valueOf()` in try-catch in CustomerCreatedHandler
- **Pros**: Resilient to malformed input; matches documented best practices
- **Cons**: Adds ~10 lines per handler
- **Effort**: Small-Medium
- **Risk**: None

### Option B: Add validation in a shared base class
- Extract validation to an abstract `WebhookEventHandler` base class
- Each handler overrides a `handleEvent()` method that receives the validated `data` Map
- **Pros**: DRY; single place for future cross-cutting concerns
- **Cons**: More structural change; introduces inheritance
- **Effort**: Medium
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: All 3 handler classes (TrialSignupHandler.cls, CustomerCreatedHandler.cls, AssetDownloadedHandler.cls)
- **Specific lines**: Lines 9-10 in each handler (JSON parsing); line 39 in CustomerCreatedHandler (date parsing)

## Acceptance Criteria

- [ ] Null/blank payload returns early without exception
- [ ] Malformed JSON returns early with error-level debug log
- [ ] Missing or non-Map `data` key returns early
- [ ] Invalid `expires_at` format is handled gracefully
- [ ] Tests cover malformed payload scenarios

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | Existing docs already warn about Payload__c null risk |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
- `docs/solutions/build-errors/salesforce-longtextarea-required-platform-event.md`
