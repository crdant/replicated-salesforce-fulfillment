---
status: pending
priority: p3
issue_id: "069"
tags:
  - code-review
  - testing
  - apex
dependencies: ["065"]
---

# Add test for bad downloaded_at timestamp fallback

## Problem Statement

The `parseDateTime` catch block (returning `DateTime.now()` for unparseable timestamps) is exercised but never tested. The `testMalformedPayload` test covers completely invalid JSON, but no test sends a well-formed payload with a bad `downloaded_at` value like `"not-a-date"`. This code path silently falls back to `DateTime.now()` and is the subject of todo 065.

## Findings

- **Agent-Native Reviewer**: Warning #2 — no test for the DateTime.now() fallback path
- **Architecture Strategist**: Test gap noted — no test for blank app_id on paid download either

## Proposed Solutions

### Option A: Add a test for bad downloaded_at (Recommended)
```apex
@IsTest
static void testBadTimestampUsesCurrentTime() {
    Account acc = createTestAccount('cust_badts', 'BadTS Corp');
    Map<String, Object> data = buildDownloadData('cust_badts', 'trial', 'app_123', 'SlackerNews');
    data.put('downloaded_at', 'not-a-date');

    Test.startTest();
    System.enqueueJob(new AssetDownloadedHandler(
        new List<Replicated_Webhook__e>{ buildEvent(data) }));
    Test.stopTest();

    List<Replicated_Download__c> downloads = [
        SELECT Downloaded_At__c FROM Replicated_Download__c WHERE Account__c = :acc.Id
    ];
    System.assertEquals(1, downloads.size());
    System.assertNotEquals(null, downloads[0].Downloaded_At__c);
}
```
- **Pros**: Exercises the catch block; documents the fallback behavior
- **Effort**: Small
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: `AssetDownloadedHandlerTest.cls`

## Acceptance Criteria

- [ ] Test sends valid event with unparseable downloaded_at
- [ ] Asserts download record is created with non-null timestamp

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from code review of PR #92 | Catch-block coverage gap |

## Resources

- PR #92: https://github.com/crdant/replicated-salesforce-fulfillment/pull/92
- Related: todo 065 (parseDateTime silent fallback)
