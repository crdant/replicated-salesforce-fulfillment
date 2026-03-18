---
title: "Salesforce Platform Event LongTextArea cannot be marked required"
category: build-errors
date: 2026-03-18
tags:
  - salesforce
  - platform-events
  - field-metadata
  - deployment
  - longtextarea
components:
  - Replicated_Webhook__e
  - Payload__c
salesforce_api_version: "61.0"
severity: blocking
resolution_time: minimal
---

## Problem

Salesforce deployment failed because the `Payload__c` LongTextArea field on the `Replicated_Webhook__e` Platform Event was marked with `<required>true</required>`. Salesforce does not allow `required=true` on LongTextArea fields for Platform Event (`__e`) objects. The metadata validation rejects this at deploy time, blocking all deployments that include the field definition.

## Root Cause

Platform Events have stricter metadata constraints than standard or custom objects. LongTextArea (and RichTextArea) fields cannot be marked `required` on Platform Event objects. The constraint exists because Platform Events are designed for high-throughput async messaging where field-level enforcement at the metadata layer is restricted for certain storage-heavy types.

This limitation is not obvious during initial metadata design since standard objects do support required LongTextArea fields.

## Investigation Steps

1. Deployment to Salesforce org failed with metadata validation error on `Payload__c`
2. Identified that LongTextArea fields cannot be `required` on Platform Event objects
3. Confirmed sibling Text fields (`Customer_Id__c`, `Event_Type__c`) can be required on Platform Events
4. Verified no Apex code currently publishes or consumes this event (infrastructure-only)
5. Confirmed the planned webhook receiver architecture validates payloads before publishing

## Solution

Changed `<required>true</required>` to `<required>false</required>` in the field metadata.

**File:** `create-license/main/default/objects/Replicated_Webhook__e/fields/Payload__c.field-meta.xml`

```diff
-    <required>true</required>
+    <required>false</required>
```

**Commit:** `17d8078`
**Branch:** `fix/claude/removes-required-from-longtextarea`

## Why This Works

The `required` constraint was never enforced by the Salesforce platform for this field type anyway — it was just blocking deployment. Removing it:

- Fixes the deployment failure
- Creates no runtime gap (the constraint was not enforced)
- Aligns with the architecture where the webhook receiver validates payloads before publishing events (Pipes and Filters pattern)

The routing fields remain required where the platform supports it:

| Field | Type | Required | Role |
|-------|------|----------|------|
| `Customer_Id__c` | Text(255) | true | Routing key |
| `Event_Type__c` | Text(255) | true | Event discriminator |
| `Payload__c` | LongTextArea(131072) | **false** | Raw JSON body |

## Prevention

### Platform Event Field Constraints

When adding fields to Platform Events, check field type compatibility:

**Support `required=true`:** Text, TextArea, Number, Date, DateTime, Boolean, Checkbox, Picklist, Email, URL, Phone, Percent, Currency

**Do NOT support `required=true`:** LongTextArea, RichTextArea

### Pre-deployment Validation

Run metadata validation locally before deploying:

```bash
sf project deploy preview --target-org shortriblabs-dev-ed
```

### Application-Level Validation

Since LongTextArea fields cannot be declaratively required, enforce the constraint in the publisher code:

```apex
if (String.isBlank(requestBody)) {
    RestContext.response.statusCode = 400;
    return;
}
```

Also add a defensive null check in subscriber triggers:

```apex
if (String.isBlank(event.Payload__c)) {
    // Log and skip — do not process events without payloads
    continue;
}
```

### Checklist for Platform Event Metadata

- [ ] All `required=true` fields use supported types (no LongTextArea/RichTextArea)
- [ ] Application-level validation covers fields that cannot be declaratively required
- [ ] `sf project deploy preview` passes locally before commit
- [ ] Unit tests assert required fields are populated on published events

## Related

- [Data Model Review & Hardening](../integration-issues/salesforce-data-model-review-hardening.md) — Documents Platform Event field constraints (Fix #5)
- [Bidirectional Sync Loop Prevention](../integration-issues/bidirectional-sync-loop-prevention.md) — SyncGuard for webhook processing
- [Event-Driven Bidirectional Sync Research](../../research/2026-03-16-event-driven-bidirectional-sync.md) — Architecture defining `Replicated_Webhook__e`
- GitHub Issue #10 — Implement webhook receiver with HMAC verification (will add publisher-side validation)
- GitHub Issues #11, #12 — Event handlers that will consume `Payload__c`
