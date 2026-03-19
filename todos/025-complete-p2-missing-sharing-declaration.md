---
status: complete
priority: p2
issue_id: "025"
tags:
  - code-review
  - security
  - sharing-model
dependencies: []
---

# Missing sharing declaration on all three handler classes

## Problem Statement

All three handler classes are declared as `public class` without a sharing keyword (`with sharing` / `without sharing` / `inherited sharing`). In Apex, omitting the keyword defaults to `without sharing` when called from a context that does not enforce sharing (Platform Event triggers, Queueable). This means SOQL queries bypass OWD and sharing rules, and DML bypasses record-level sharing enforcement.

Since these are system-level automation handlers processing webhook events, `without sharing` may be the correct intent — but it should be declared explicitly.

This finding was identified by security-sentinel.

## Findings

- **Security Sentinel**: Finding #1 (MEDIUM) — implicit `without sharing` is a compliance risk for Salesforce security reviews and makes the security intent unclear for future maintainers.

## Proposed Solutions

### Option A: Declare `without sharing` with comment (Recommended)
- Add `without sharing` to all three class declarations with a comment explaining why
- These are system-level handlers that need to query/modify records regardless of running user context
- **Pros**: Explicit intent; satisfies security review requirements
- **Cons**: None
- **Effort**: Small (3 lines + comments)
- **Risk**: None — behavior unchanged

### Option B: Declare `inherited sharing`
- Inherits sharing context from the caller
- **Pros**: More flexible; correct for classes that might be called from user context later
- **Cons**: In Platform Event context, still resolves to `without sharing`
- **Effort**: Small
- **Risk**: Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `TrialSignupHandler.cls` (line 1), `CustomerCreatedHandler.cls` (line 1), `AssetDownloadedHandler.cls` (line 1)

## Acceptance Criteria

- [ ] All three handlers have an explicit sharing keyword
- [ ] Comment explains the sharing decision

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #50 | Existing classes (ReplicatedFulfillment, etc.) also lack sharing declaration |

## Resources

- PR #50: https://github.com/crdant/replicated-salesforce-fulfillment/pull/50
- [Apex Sharing Keywords](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_keywords_sharing.htm)
