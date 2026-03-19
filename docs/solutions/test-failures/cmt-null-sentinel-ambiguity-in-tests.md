---
title: "testMissingWebhookSecret fails with 401 instead of 500 due to CMT visibility in test context"
category: test-failures
date: 2026-03-18
tags:
  - apex-testing
  - custom-metadata-types
  - webhook
  - hmac
  - test-isolation
  - null-sentinel
severity: medium
components:
  - ReplicatedWebhookReceiver
  - ReplicatedWebhookReceiverTest
related_issues:
  - "#10"
  - "#26"
  - "#51"
---

# testMissingWebhookSecret Fails with 401 Instead of 500 Due to CMT Visibility in Test Context

## Problem

`ReplicatedWebhookReceiverTest.testMissingWebhookSecret` expected HTTP 500 (server configuration error) but received HTTP 401 (invalid signature).

The test intentionally skipped calling `setupTestSecret()` to simulate a missing webhook secret, expecting the receiver to detect no configured secret and return 500. Instead, signature verification ran against a real secret and failed, producing 401.

## Root Cause

The null sentinel pattern used to inject test values was ambiguous. `testSecret = null` conflated two distinct states: "the test has not overridden this value" and "the test has explicitly overridden this to null."

```apex
@TestVisible
private static String testSecret = null;

private static String getWebhookSecret() {
    if (testSecret != null) {
        return testSecret;
    }
    // Falls through to real CMT query
    List<Replicated_Webhook_Secret__mdt> secrets = [
        SELECT Secret__c
        FROM Replicated_Webhook_Secret__mdt
        WHERE DeveloperName = 'Default'
        LIMIT 1
    ];
    if (secrets.isEmpty()) { return null; }
    return secrets[0].Secret__c;
}
```

When `testSecret` was null (the default), the guard `if (testSecret != null)` evaluated to false, and the method fell through to query `Replicated_Webhook_Secret__mdt` via SOQL.

The critical detail: Custom Metadata Type records are visible in Apex test context without `@IsTest(SeeAllData=true)`. Unlike standard or custom sObjects, CMT records are part of the org's metadata and are always accessible. The org had a live `Replicated_Webhook_Secret__mdt` record with `DeveloperName='Default'`, so the query returned the real secret.

With a real secret loaded and a bogus signature (`sha256=anything`), HMAC verification ran and failed, returning 401 instead of the expected 500.

## Solution

Introduce a separate boolean flag `testSecretOverridden` to decouple "is the test in control of this value?" from "what value should be returned?"

**Before:**

```apex
@TestVisible
private static String testSecret = null;

private static String getWebhookSecret() {
    if (testSecret != null) {
        return testSecret;
    }
    // Falls through to real CMT query
}
```

**After:**

```apex
@TestVisible
private static String testSecret = null;

@TestVisible
private static Boolean testSecretOverridden = false;

private static String getWebhookSecret() {
    if (testSecretOverridden) {
        return testSecret;  // Returns null when testSecret was never set
    }
    // Falls through to real CMT query
}
```

**Test helper updated to set both fields:**

```apex
private static void setupTestSecret() {
    ReplicatedWebhookReceiver.testSecret = TEST_SECRET;
    ReplicatedWebhookReceiver.testSecretOverridden = true;
}
```

**Failing test updated to explicitly opt in to override mode:**

```apex
@IsTest
static void testMissingWebhookSecret() {
    // Opt in to override mode but leave testSecret null
    // getWebhookSecret() returns null -> 500
    ReplicatedWebhookReceiver.testSecretOverridden = true;
    String body = validPayload('customer.created');

    RestContext.request = buildRequest(body, 'sha256=anything');
    RestContext.response = new RestResponse();

    Test.startTest();
    ReplicatedWebhookReceiver.handlePost();
    Test.stopTest();

    System.assertEquals(500, RestContext.response.statusCode,
        'Missing webhook secret should return 500');
}
```

## Verification

The fix is correct because:

1. Tests that call `setupTestSecret()` set both `testSecretOverridden = true` and `testSecret = TEST_SECRET`. The gate opens and returns the test value. Behavior unchanged.

2. Tests that do not call `setupTestSecret()` leave `testSecretOverridden = false`. The gate stays closed and the real CMT query runs. Behavior unchanged.

3. `testMissingWebhookSecret` sets `testSecretOverridden = true` but leaves `testSecret = null`. The gate opens, null is returned, the receiver detects no configured secret, and returns 500 as expected.

All 8 tests in `ReplicatedWebhookReceiverTest` pass after this change, including `testMissingWebhookSecret`.

## Prevention

### Avoid ambiguous null sentinels in test infrastructure

When using `@TestVisible` static fields for dependency injection in Apex, do not rely on `null` as the "not configured" signal if the fallback path has observable side effects in test context. Use an explicit boolean gate:

```apex
// Fragile: null means both "not injected" and "no value"
if (testValue != null) { return testValue; }

// Explicit: boolean separates "injected?" from "what value?"
if (testValueOverridden) { return testValue; }
```

### Understand CMT visibility in test context

Custom Metadata Type records sit outside the standard test data isolation boundary. They are always visible in tests regardless of `SeeAllData`. This means:

- A CMT query in a fallback path will return real org records during a test run
- A test that "works" because the injection is active also "works" when the injection is broken — because the CMT fallback silently provides the real value
- The test passes without validating that the injection is actually being used

Treat any test that queries CMT as having an implicit dependency on org configuration.

### Code review checklist

When reviewing code that uses a null-based fallback to a CMT query:

- [ ] Is `null` being used to mean both "not injected by caller" and "not found in CMT"? If so, require explicit state separation
- [ ] Does the test inject a dependency and then assert the injected value was actually used?
- [ ] Is there a test that verifies behavior when the config is intentionally absent? Does it make the CMT fallback unreachable?
- [ ] Can the CMT query path be reached in tests without the author intending it?

### General principle

Null is a value, not a signal. When a field needs to represent three states — "not set by the test," "set to a real value," and "set to absent" — null can only encode two of them. Add a boolean flag, a sentinel constant, or a provider interface to make all states explicit.

## Related Documentation

- [Webhook Receiver HMAC Verification](../integration-issues/webhook-receiver-hmac-verification.md) — Original implementation including the `@TestVisible` pattern for secret injection
- [Webhook Receiver Code Review Findings](../security-issues/webhook-receiver-code-review-findings.md) — Security hardening review from PR #26
- [Webhook Endpoint Testing Integration](../integration-issues/salesforce-webhook-endpoint-testing-integration.md) — End-to-end testing against live Salesforce Site, CMT provisioning via `sf cmdt generate record`
- [Secret Storage Evaluation for CMT Credentials](../security-issues/secret-storage-evaluation-for-cmt-credentials.md) — Evaluated Protected CMT vs Named Credentials for secret storage

### Related Issues

| Issue | Relationship |
|-------|-------------|
| #10 | Implement webhook receiver — introduced the `testSecret` pattern |
| #26 | Security code review of webhook receiver |
| #51 | PR where the bug was discovered and fixed |
