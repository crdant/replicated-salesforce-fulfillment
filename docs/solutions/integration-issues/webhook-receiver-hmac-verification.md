---
title: Implement HMAC-Verified Webhook Receiver for Replicated Platform Events
category: integration-issues
date: 2026-03-16
tags:
  - webhook-receiver
  - hmac-signature-verification
  - platform-events
  - salesforce-integration
  - replicated-platform
  - apex-rest
  - custom-metadata-testing
components:
  - ReplicatedWebhookReceiver
  - ReplicatedWebhookSubscriber
  - ReplicatedWebhookReceiverTest
  - Replicated_Webhook__e
  - Replicated_Webhook_Secret__mdt
severity: high
resolution_time: 2-3 hours
related_issues:
  - "#10 (this issue)"
  - "#7 (Platform Event and webhook secret metadata - dependency)"
  - "#6 (parent epic - bidirectional sync)"
  - "#11, #12 (event handlers - blocked by this)"
  - "#9 (SyncGuard - consumed by webhook handlers)"
related_docs:
  - docs/solutions/integration-issues/bidirectional-sync-loop-prevention.md
  - docs/solutions/integration-issues/salesforce-data-model-review-hardening.md
  - docs/research/2026-03-16-event-driven-bidirectional-sync.md
---

# Webhook Receiver with HMAC Signature Verification

## Problem

Need a Salesforce REST endpoint to receive Replicated webhook POSTs, verify HMAC-SHA256 signatures, and publish Platform Events for async processing. The endpoint is the "front door" for all inbound Replicated events in the bidirectional sync system.

**Constraints:**
- Must respond within 5 seconds (Replicated webhook timeout)
- Salesforce triggers can't make HTTP callouts, so processing must be decoupled from receipt
- Custom metadata types (`Replicated_Webhook_Secret__mdt`) can't be inserted in Apex test context
- Need reliable event delivery with replay capability

## Root Cause / Design Challenges

1. **Decoupling requirement**: Webhook receipt and event processing must be separate transactions. The receiver publishes a Platform Event; subscriber triggers handle processing asynchronously.
2. **Custom metadata in tests**: `Replicated_Webhook_Secret__mdt` records exist only when deployed to the org. Standard Apex tests can't insert custom metadata, requiring an injectable test pattern.
3. **Timeout pressure**: Replicated's 5-second timeout means the synchronous path must be minimal: verify, parse, publish, return.

## Solution

### Architecture

```
Replicated POST -> ReplicatedWebhookReceiver (@RestResource)
  1. Extract X-Replicated-Signature header -> 401 if missing
  2. Verify HMAC-SHA256(body, secret) -> 401 if mismatch
  3. Parse JSON payload -> 400 if malformed
  4. Extract event type -> 400 if missing
  5. Publish Replicated_Webhook__e Platform Event -> 200
       |
       v
  ReplicatedWebhookSubscriber (after insert trigger)
  -> Routes by Event_Type__c (stub router, handlers in #11/#12)
  -> setResumeCheckpoint() for reliable replay
```

### HMAC-SHA256 Verification

Replicated sends `X-Replicated-Signature: sha256=<hex-encoded-hmac>`. Verification in Apex:

```apex
private static Boolean verifySignature(String body, String signature, String secret) {
    if (!signature.startsWith('sha256=')) {
        return false;
    }
    Blob mac = Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(body),
        Blob.valueOf(secret)
    );
    String expected = 'sha256=' + EncodingUtil.convertToHex(mac);
    return constantTimeEquals(expected, signature);
}

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

The secret is retrieved from `Replicated_Webhook_Secret__mdt` (DeveloperName = 'Default').

### TestVisible Secret Override Pattern

Custom metadata can't be inserted in test context. The solution uses a `@TestVisible` static field:

```apex
@TestVisible
private static String testSecret = null;

private static String getWebhookSecret() {
    if (testSecret != null) {
        return testSecret;
    }
    List<Replicated_Webhook_Secret__mdt> secrets = [
        SELECT Secret__c
        FROM Replicated_Webhook_Secret__mdt
        WHERE DeveloperName = 'Default'
        LIMIT 1
    ];
    if (secrets.isEmpty()) {
        return null;
    }
    return secrets[0].Secret__c;
}
```

Tests inject the secret before calling `handlePost()`:

```apex
private static void setupTestSecret() {
    ReplicatedWebhookReceiver.testSecret = TEST_SECRET;
}
```

### Platform Event Publishing

The receiver publishes `Replicated_Webhook__e` with three fields from the webhook payload:

```apex
Replicated_Webhook__e event = new Replicated_Webhook__e(
    Event_Type__c = eventType,        // from payload.event
    Payload__c = body,                // raw JSON body
    Customer_Id__c = customerId       // from payload.data.customer_id
);
Database.SaveResult sr = EventBus.publish(event);
```

### Subscriber Trigger with Resume Checkpoint

```apex
trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    for (Replicated_Webhook__e event : Trigger.New) {
        // Avoid logging payload or customer data -- debug logs are visible to admins.
        switch on event.Event_Type__c {
            when else {
                System.debug('Unhandled Replicated webhook event type: ' + event.Event_Type__c);
            }
        }
    }
    EventBus.TriggerContext.currentContext().setResumeCheckpoint(
        Trigger.New[Trigger.New.size() - 1].ReplayId
    );
}
```

`setResumeCheckpoint()` marks the last successfully processed event. If the trigger fails, Salesforce replays events from the last checkpoint.

### HTTP Response Codes

| Status | Condition |
|--------|-----------|
| 200 | Event published successfully |
| 400 | Malformed JSON or missing event type |
| 401 | Missing, invalid, or unsupported algorithm HMAC signature |
| 413 | Payload exceeds 100K character limit |
| 500 | Platform Event publish failure or missing webhook secret |

### Test Coverage

8 test methods covering all acceptance criteria:

| Test Method | Scenario | Expected |
|-------------|----------|----------|
| testValidSignature | Valid HMAC + valid payload | 200 |
| testInvalidSignature | Wrong HMAC value | 401 |
| testMissingSignature | No X-Replicated-Signature header | 401 |
| testUnsupportedSignatureAlgorithm | Non-sha256 prefix (e.g. `sha1=`) | 401 |
| testMalformedJson | Unparseable body | 400 |
| testMissingEventType | Valid JSON, no `event` field | 400 |
| testPayloadTooLarge | Body exceeds 100K character limit | 413 |
| testMissingWebhookSecret | No metadata record configured | 500 |

## Prevention Strategies

### Custom Metadata Testing
- Use the `@TestVisible` static field pattern consistently across all classes that read custom metadata
- Keep `@TestVisible` scope minimal (on the getter, not scattered through business logic)
- Document why the pattern is needed in test class comments

### Webhook Timeout (5-Second Window)
- **Synchronous boundary rule**: anything in the webhook handler must complete in under 2 seconds (leaving 3s safety margin)
- Never add business logic, SOQL queries for records, or API callouts to the receiver
- The receiver's only job: verify, parse, publish, return

### Bidirectional Sync Loops
- Webhook subscriber handlers must add record IDs to `SyncGuard.inboundSyncIds` before DML
- Outbound triggers check `SyncGuard.inboundSyncIds.contains(id)` and skip if present
- Static sets reset at async boundaries; combine with `Last_Synced_By__c` for cross-transaction safety

### Platform Event Reliability
- `setResumeCheckpoint()` should be called after successful processing (current implementation calls it at the end of the trigger)
- Platform Events retain for 24 hours; monitoring must catch failures within that window
- Track ReplayId advancement to verify events are being processed

### HMAC Signature Security
- Validate the `sha256=` prefix before comparing (reject unknown algorithms)
- Use constant-time comparison to prevent timing attacks (XOR-based loop, not `String.equals()`)
- Never log full signatures or secrets
- Rotate webhook secrets periodically (update `Replicated_Webhook_Secret__mdt`)
- `Replicated_Webhook_Secret__mdt.Secret__c` is stored as plaintext; for production orgs with strict security requirements, consider Named Credentials or Shield Platform Encryption

## Webhook Payload Format

Reference payload structure from Replicated:

```json
{
  "event": "customer.created",
  "timestamp": "2026-01-25T22:48:32Z",
  "text": "Human-readable description",
  "data": {
    "app_id": "...",
    "team_id": "...",
    "customer_id": "...",
    "customer_name": "...",
    "channel_id": "...",
    "license_type": "trial",
    "expires_at": "2026-02-24T22:47:37Z"
  }
}
```

## Files Created

| File | Purpose |
|------|---------|
| `classes/ReplicatedWebhookReceiver.cls` | `@RestResource(urlMapping='/replicated/webhook')` |
| `classes/ReplicatedWebhookReceiverTest.cls` | 8 test methods |
| `triggers/ReplicatedWebhookSubscriber.trigger` | Platform Event subscriber with stub router |

## Anti-Patterns to Avoid

- Querying records or making callouts in the webhook handler (timeout risk)
- Optional routing fields on Platform Events (silent event drops - `Customer_Id__c` should always have a value)
- Setting `setResumeCheckpoint()` before processing (events lost if handler fails)
- Using simple `==` without validating signature format prefix
- Adding `SyncGuard` IDs after DML (triggers already fired)

## Related Documentation

- [Bidirectional Sync Loop Prevention](bidirectional-sync-loop-prevention.md) - SyncGuard pattern used by webhook handlers
- [Salesforce Data Model Review](salesforce-data-model-review-hardening.md) - Platform Event and metadata type definitions
- [Event-Driven Bidirectional Sync Research](../../research/2026-03-16-event-driven-bidirectional-sync.md) - Architecture design and webhook payload format
