---
status: complete
priority: p3
issue_id: "014"
tags:
  - code-review
  - security
  - apex
  - hardening
dependencies: []
---

# Add explicit sharing declarations to Apex classes

## Problem Statement

None of the Apex classes in the project (`ReplicatedFulfillment`, `OrderTerms`, `ReplicatedCustomer`, `ReplicatedPlatform`, `SyncGuard`) declare `with sharing` or `without sharing`. They currently run in system context (invoked from triggers), so they bypass FLS and sharing rules correctly. However, this is fragile: if any class is later invoked from a user context (Lightning component, Flow, etc.), sharing behavior becomes ambiguous and inherits the caller's context.

## Findings

- **Agent-Native Reviewer**: No explicit sharing declarations on any Apex class. Currently safe because trigger context = system context. But fragile if invocation context changes.

## Proposed Solutions

### Option A: Add `without sharing` to system-context classes (Recommended)

Add `without sharing` to `ReplicatedFulfillment`, `OrderTerms`, `ReplicatedCustomer`, and `ReplicatedPlatform` since they perform system-level operations that should always bypass sharing rules.

- **Pros**: Makes intent explicit, protects against future invocation context changes
- **Cons**: Minor code change across multiple files
- **Effort**: Small (4 class declarations)
- **Risk**: None — matches current runtime behavior

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**:
  - `create-license/main/default/classes/ReplicatedFulfillment.cls` (line 1)
  - `create-license/main/default/classes/OrderTerms.cls` (line 1)
  - `create-license/main/default/classes/ReplicatedCustomer.cls` (line 1)
  - `create-license/main/default/classes/ReplicatedPlatform.cls` (line 1)

## Acceptance Criteria

- [ ] All system-context Apex classes declare `without sharing`
- [ ] SyncGuard evaluated separately (utility class, may not need sharing declaration)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #52 | Agent-native reviewer flagged as forward-looking hardening |

## Resources

- PR #52: https://github.com/crdant/replicated-salesforce-fulfillment/pull/52
- Salesforce sharing docs: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_keywords_sharing.htm
