---
title: "Salesforce Webhook Endpoint Testing - HTTP/2, CLI, and Site Configuration"
category: integration-issues
date: 2026-03-18
tags:
  - webhooks
  - salesforce-sites
  - curl
  - http2
  - custom-metadata
  - sf-cli
  - testing
  - operational-tooling
components:
  - hack/set-webhook-secret
  - hack/test-webhook
  - Makefile
  - Salesforce Site configuration
  - Replicated_Webhook_Secret__mdt
severity: medium
resolution_time: single-session
related_issues:
  - "#10 (webhook receiver implementation)"
  - "#21 (secret storage evaluation)"
related_docs:
  - docs/solutions/integration-issues/webhook-receiver-hmac-verification.md
  - docs/solutions/security-issues/webhook-receiver-code-review-findings.md
  - docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md
  - docs/solutions/integration-issues/salesforce-data-model-review-hardening.md
---

# Salesforce Webhook Endpoint Testing - HTTP/2, CLI, and Site Configuration

## Problem

End-to-end testing of the webhook receiver (`ReplicatedWebhookReceiver`) against a live Salesforce Site surfaced four distinct integration issues:

1. **`hack/set-webhook-secret` used a non-existent SF CLI command** — `sf org create custom-metadata-record` does not exist, causing `make webhook-secret` to fail.
2. **curl returned false HTTP 401 responses** — all webhook POSTs appeared to fail with 401 and no response body, but the endpoint was actually returning 200 OK.
3. **Salesforce Site URL path retained a typo** — changing Site Label and Site Name did not update the Default Web Address field.
4. **Makefile org alias inconsistency** — `webhook-secret` target used `${ORG_ALIAS}` while other targets hardcoded `shortrib`.

## Root Cause

### 1. Non-existent SF CLI command

The `hack/set-webhook-secret` script called `sf org create custom-metadata-record`, which is not a valid command. The correct approach for Custom Metadata records via CLI is `sf cmdt generate record` (creates a local XML file) followed by `sf project deploy start` (deploys it to the org). The command was likely hallucinated during initial implementation.

### 2. curl HTTP/2 incompatibility with Salesforce Sites

curl's HTTP/2 (h2) implementation has a compatibility issue with Salesforce Sites' response handling. The symptom is:

- HTTP status reported as 401
- No response body received (0 bytes)
- curl exit code 56
- Error: `process_pending_input: nghttp2_session_mem_recv() returned -902`

The endpoint was returning `{"status":"ok"}` with HTTP 200 the entire time. The issue is purely at the protocol level — curl negotiates HTTP/2 with the server, but the response stream is corrupted during h2 frame processing.

### 3. Salesforce Site URL path is independent from label

Salesforce Sites have three separate fields:

- **Site Label** — display name in Setup UI
- **Site Name** — internal API identifier
- **Default Web Address** — the actual URL path segment

These are completely decoupled. Changing Label/Name from `wehooks` to `webhooks` left the Default Web Address at `wehooks`. Requests to `/webhooks/` returned 404 while `/wehooks/` still worked (returning 401 due to the curl/H2 bug, masking the real response).

### 4. Makefile inconsistency

The `webhook-secret` target used `${ORG_ALIAS}` (environment variable) while `deploy`, `retrieve`, and other targets hardcoded `shortrib`. Running `make webhook-secret` without setting the variable passed an empty string.

## Solution

### Fix 1: Replace CLI command with two-step generate + deploy

```bash
# Generate the custom metadata record file locally
sf cmdt generate record \
    --type-name Replicated_Webhook_Secret__mdt \
    --record-name Default \
    --label Default \
    --output-directory "$CMDT_DIR" \
    --input-directory "$PROJECT_DIR/create-license/main/default/objects" \
    "Secret__c=$SECRET"

# Deploy the generated file to the org
sf project deploy start \
    --source-dir "$CMDT_DIR/Replicated_Webhook_Secret.Default.md-meta.xml" \
    --target-org "$ORG_ALIAS"
```

Important: the generated filename is `Replicated_Webhook_Secret.Default.md-meta.xml` — no `__mdt` suffix in the filename, even though the type name includes it.

### Fix 2: Force HTTP/1.1 in curl

```bash
# Before (fails silently with false 401):
curl -s -X POST "${SITE_URL}/services/apexrest/replicated/webhook" ...

# After (works correctly):
curl --http1.1 -s -X POST "${SITE_URL}/services/apexrest/replicated/webhook" ...
```

### Fix 3: Manually update Default Web Address field

In Setup > Sites > click Site name > edit the **Default Web Address** field separately from the label. The label change does not propagate to the URL path.

### Fix 4: Hardcode org alias consistently

```makefile
webhook-secret:
	hack/set-webhook-secret -o shortrib -s "${REPLICATED_WEBHOOK_SECRET}"
```

## Prevention Strategies

### SF CLI command verification

- Run `sf commands | grep <keyword>` before embedding commands in scripts
- Use `sf <command> --help` to verify exact flag syntax
- Test the complete command interactively before scripting it

### curl and Salesforce Sites

- **Always use `--http1.1` when testing Salesforce Site endpoints** — HTTP/2 can produce false error responses
- When debugging unexpected 401s, test with both `--http1.1` and `-v` (verbose) before investigating auth issues
- If curl returns exit code 56 with `nghttp2` errors, suspect HTTP/2 incompatibility first

### Salesforce Site setup checklist

- [ ] Register Sites domain (one-time, manual)
- [ ] Create Site with correct **Default Web Address** (this is the URL path)
- [ ] Verify Default Web Address field separately from Site Label
- [ ] Activate the Site
- [ ] Grant `ReplicatedWebhookReceiver` to guest user profile via Public Access Settings > Apex Class Access
- [ ] Test the actual URL with `hack/test-webhook` before configuring external systems

### Makefile conventions

- Use the same org alias approach (hardcoded or variable) across all targets
- If the project only targets one org, hardcode it for simplicity
- If variable, define with `?=` default at the top of the Makefile

## Debugging Timeline

| Step | Observation | Actual Cause |
|------|-------------|--------------|
| `make webhook-secret` | "not a sf command" | Non-existent CLI command |
| POST to `/webhooks/` | 404 | Default Web Address was still `wehooks` |
| POST to `/wehooks/` | 401 (no body) | curl HTTP/2 bug — endpoint was returning 200 |
| POST with `--http1.1` | 200 `{"status":"ok"}` | Working correctly all along |

The layered failures made diagnosis harder — the URL typo caused 404, which led to testing the old URL, which appeared to return 401 due to the HTTP/2 bug. Only after fixing the URL path *and* switching to HTTP/1.1 did the endpoint return the expected 200.
