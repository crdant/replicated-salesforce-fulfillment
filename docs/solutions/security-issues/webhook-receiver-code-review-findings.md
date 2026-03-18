---
title: "Webhook Receiver Security & Reliability Hardening"
category: security-issues
date: 2026-03-17
tags:
  - webhook-security
  - hmac-verification
  - timing-attacks
  - constant-time-comparison
  - payload-validation
  - salesforce-platform-events
  - code-review
  - defensive-coding
  - operational-tooling
  - secret-management
components:
  - ReplicatedWebhookReceiver
  - ReplicatedWebhookReceiverTest
  - ReplicatedWebhookSubscriber
severity: high
resolution_time: single-pass
related_issues:
  - "#10 (webhook receiver implementation)"
  - "#26 (PR reviewed)"
  - "#7 (Platform Event and metadata - dependency)"
  - "#6 (parent epic - bidirectional sync)"
  - "#11, #12 (event handlers - blocked by #10)"
  - "#21 (secret storage evaluation)"
related_docs:
  - docs/solutions/integration-issues/webhook-receiver-hmac-verification.md
  - docs/solutions/integration-issues/bidirectional-sync-loop-prevention.md
  - docs/solutions/integration-issues/salesforce-data-model-review-hardening.md
  - docs/research/2026-03-16-event-driven-bidirectional-sync.md
---

# Webhook Receiver Security & Reliability Hardening

## Problem

A multi-agent code review of PR #26 (`ReplicatedWebhookReceiver`) identified 10 findings across security, reliability, and operational concerns:

- **Timing attacks** on HMAC signature verification via `String.equals()`
- **Silent data loss** from oversized payloads truncating in Platform Event fields
- **Uncaught exceptions** when webhook secret metadata is missing
- **Missing protocol validation** for signature algorithm prefix
- **Incomplete HTTP semantics** (no Content-Type header)
- **Test bloat** with duplicate coverage and gaps in edge cases
- **Information leakage** in debug logs
- **Operational friction** with manual secret configuration

The review used 6 specialized agents: security-sentinel, architecture-strategist, performance-oracle, code-simplicity-reviewer, agent-native-reviewer, and learnings-researcher.

## Root Cause

1. **Timing attack**: `String.equals()` short-circuits on first mismatch, allowing byte-by-byte signature forgery through response time measurement.
2. **Payload truncation**: No length validation before publishing. `Payload__c` (LongTextArea, 131,072 chars) silently truncates without error, so the receiver returns 200 while downstream handlers receive corrupt JSON.
3. **Exception handling**: Direct SOQL assignment (`Replicated_Webhook_Secret__mdt secret = [SELECT ...]`) throws `QueryException` when no rows exist, leaking stack traces in the REST response.
4. **Missing prefix validation**: Accepted any signature format, not just `sha256=...`.
5. **Test debt**: Three tests duplicated happy-path coverage while missing error conditions (413, 500, unsupported algorithm).
6. **No CLI provisioning**: Webhook secret required manual Salesforce Setup UI intervention.

## Solution

### Security Hardening

**Constant-time HMAC comparison** replaces `String.equals()` with XOR-based loop:

```apex
private static Boolean constantTimeEquals(String a, String b) {
    if (a.length() != b.length()) {
        return false;
    }
    Integer result = 0;
    for (Integer i = 0; i < a.length(); i++) {
        result |= a.charAt(i) ^ b.charAt(i);
    }
    return result == 0;
}
```

All comparisons take the same wall-clock time regardless of where bytes differ. The length check is safe because HMAC hex digests are always 71 characters (`sha256=` + 64 hex).

**Signature algorithm validation** rejects non-SHA256 signatures early:

```apex
if (!signature.startsWith('sha256=')) {
    return false;
}
```

### Defensive Error Handling

**Payload size guard** prevents silent Platform Event field truncation:

```apex
private static final Integer MAX_PAYLOAD_LENGTH = 100000;

if (body.length() > MAX_PAYLOAD_LENGTH) {
    res.statusCode = 413;
    res.responseBody = Blob.valueOf('{"error":"Payload too large"}');
    return;
}
```

**Defensive secret retrieval** uses list-based SOQL with explicit empty check:

```apex
List<Replicated_Webhook_Secret__mdt> secrets = [
    SELECT Secret__c FROM Replicated_Webhook_Secret__mdt
    WHERE DeveloperName = 'Default' LIMIT 1
];
if (secrets.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'Webhook secret not configured');
    return null;
}
return secrets[0].Secret__c;
```

The caller returns 500 with `{"error":"Server configuration error"}` instead of a stack trace.

**Content-Type header** set explicitly on all responses:

```apex
res.addHeader('Content-Type', 'application/json');
```

### Test Quality

Removed 3 redundant tests that duplicated `testValidSignature` coverage:
- `testCustomerCreatedEvent` (same path, different event string)
- `testInstanceCreatedEvent` (same path, different event string)
- `testVerifySignatureDirectly` (private method already covered by integration tests)

Added 3 tests covering new code paths:
- `testUnsupportedSignatureAlgorithm` (sha1= prefix returns 401)
- `testPayloadTooLarge` (>100K chars returns 413)
- `testMissingWebhookSecret` (no metadata record returns 500)

Net result: same test count (8), but every test exercises a unique code path.

### Operational Parity

**`make webhook-secret` target** mirrors `make credentials`:

```makefile
webhook-secret:
	hack/set-webhook-secret -o "${ORG_ALIAS}" -s "${REPLICATED_WEBHOOK_SECRET}"
```

**`hack/set-webhook-secret`** provisions the Custom Metadata record via CLI.

**`hack/test-webhook`** computes an HMAC-SHA256 signature and sends a test POST with curl, providing end-to-end validation without the Salesforce UI.

**Subscriber trigger logging** cleaned up: removed `Customer_Id__c` from debug output, added comment warning against logging sensitive data.

## Prevention Strategies

### Security

- **Always use constant-time comparison** for cryptographic values. In Apex, XOR-based loops are the only option since the platform has no built-in constant-time string compare.
- **Validate algorithm prefixes** before cryptographic operations. Reject unexpected formats early.
- **Validate input size against destination field limits** before processing. Silent truncation is worse than a loud 413.
- **Never log sensitive identifiers** (customer IDs, tokens, signatures) in Salesforce debug logs. Logs are visible to all admins and retained for 24 hours.
- `Replicated_Webhook_Secret__mdt.Secret__c` is stored as plaintext. For production orgs, evaluate Named Credentials or Shield Platform Encryption.

### Error Handling

- **Never use bare SOQL assignment** in code paths exposed to external callers. Always query into a list with explicit empty check.
- **Set Content-Type headers explicitly** on all REST responses.
- **Treat missing configuration as 500**, not an unhandled exception. Log the specific missing item for operators.

### Testing

- **Map each test to a unique code path.** If two tests exercise the same branches, one is redundant.
- **Test every HTTP status code** the endpoint can return, including error paths.
- **Remove `@TestVisible`** from methods once direct tests are deleted. Keep the test surface minimal.

### Operations

- **Every configuration step needs a CLI path.** If it requires the Salesforce Setup UI, add a Makefile target or hack script.
- **Provide a curl validation script** for webhook endpoints. Computing HMAC signatures by hand is error-prone.

## Code Review Checklist for Webhook/Security Code

### Security
- [ ] Cryptographic comparisons use constant-time algorithms
- [ ] Algorithm/version prefixes validated before comparison
- [ ] Signature verification happens before any business logic
- [ ] No sensitive data logged to debug logs
- [ ] Error messages do not leak stack traces or schema info
- [ ] Input size validated against destination field limits

### Error Handling
- [ ] No bare SOQL assignments in external code paths
- [ ] All exceptions converted to appropriate HTTP status codes
- [ ] Configuration errors return 500 with clean message
- [ ] Response headers include explicit Content-Type

### Testing
- [ ] Each test exercises a unique code path
- [ ] All HTTP status codes have corresponding tests
- [ ] Error paths tested (not just happy paths)
- [ ] `@TestVisible` annotations are minimal

### Operations
- [ ] Configuration steps have CLI-automatable paths
- [ ] Deployment checklist includes configuration verification
- [ ] Validation script provided for manual testing

## Findings Summary

| # | Category | Finding | Fix | Severity |
|---|----------|---------|-----|----------|
| 1 | Security | Timing attack via String.equals() | Constant-time XOR comparison | P1 |
| 2 | Reliability | Silent payload truncation | 413 with size guard | P1 |
| 3 | Reliability | Unhandled missing secret exception | List-based SOQL + null check | P2 |
| 4 | Security | No signature prefix validation | startsWith('sha256=') check | P2 |
| 5 | Operations | No webhook secret automation | make webhook-secret target | P2 |
| 6 | Testing | 3 redundant tests, 3 missing | Replaced with meaningful tests | P2 |
| 7 | HTTP | Missing Content-Type header | addHeader on all responses | P3 |
| 8 | Security | Plaintext secret in CMT | Documented risk, noted alternatives | P3 |
| 9 | Security | Customer ID in debug logs | Removed from trigger output | P3 |
| 10 | Operations | No curl validation script | hack/test-webhook script | P3 |

## Related Documentation

- [Webhook Receiver Implementation Patterns](../integration-issues/webhook-receiver-hmac-verification.md) -- companion doc covering architecture, flow, and test patterns
- [Bidirectional Sync Loop Prevention](../integration-issues/bidirectional-sync-loop-prevention.md) -- SyncGuard pattern used by downstream handlers
- [Salesforce Data Model Review & Hardening](../integration-issues/salesforce-data-model-review-hardening.md) -- Platform Event and CMT definitions
- [Wrong Identifier Type in API Call](../integration-issues/wrong-identifier-type-in-api-call.md) -- customer ID field semantics
- [Event-Driven Bidirectional Sync Research](../../research/2026-03-16-event-driven-bidirectional-sync.md) -- architecture and payload format

### GitHub Issues

- [#6](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6) -- Parent epic (bidirectional sync)
- [#10](https://github.com/crdant/replicated-salesforce-fulfillment/issues/10) -- Webhook receiver implementation
- [#11](https://github.com/crdant/replicated-salesforce-fulfillment/issues/11), [#12](https://github.com/crdant/replicated-salesforce-fulfillment/issues/12) -- Event handlers (blocked by #10)
- [#21](https://github.com/crdant/replicated-salesforce-fulfillment/issues/21) -- Secret storage evaluation
