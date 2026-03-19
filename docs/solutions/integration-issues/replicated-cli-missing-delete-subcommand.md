---
title: "Replicated CLI missing DELETE subcommand causes silent failure in bash scripts"
category: "integration-issues"
date: 2026-03-19
tags:
  - replicated-cli
  - makefile
  - api-integration
  - curl
  - vendor-api
  - silent-failure
severity: "high"
components:
  - "hack/clean-webhook-subscription"
  - "Replicated Vendor Portal API"
  - "replicated CLI"
---

# Replicated CLI missing DELETE subcommand causes silent failure in bash scripts

## Problem

A bash script used `replicated api delete "/v3/notification_subscription/${id}"` to remove a webhook subscription. The command printed CLI usage help to stdout and exited with code 0 — no error, no deletion. The `replicated api` command only supports `get`, `patch`, `post`, and `put`. There is no `delete` subcommand.

**Symptoms:**
- Script prints "Deleting subscription ..." followed by the `replicated api` usage help block
- Subscription remains in the Replicated Vendor Portal
- Exit code is 0, so `set -euo pipefail` does not catch the failure

## Root Cause

The `replicated` CLI treats unrecognized subcommands as a help request — it prints usage information and exits 0 instead of returning a nonzero exit code. This means `set -euo pipefail` cannot detect the failure, and any script that assumes exit 0 means success will silently skip the operation.

Available `replicated api` subcommands (as of CLI v0.124.3):
```
get     Make ad-hoc GET API calls to the Replicated API
patch   Make ad-hoc PATCH API calls to the Replicated API
post    Make ad-hoc POST API calls to the Replicated API
put     Make ad-hoc PUT API calls to the Replicated API
```

No `delete` subcommand exists.

## Solution

Use `curl -s -X DELETE` directly against the Replicated Vendor API. Authenticate with `REPLICATED_SERVICE_ACCOUNT_TOKEN` in the `Authorization` header.

```bash
: "${REPLICATED_SERVICE_ACCOUNT_TOKEN:?REPLICATED_SERVICE_ACCOUNT_TOKEN is not set}"

API_BASE="https://api.replicated.com/vendor"

# LIST still works fine with the CLI
response=$(replicated api get /v3/notification_subscriptions)

# DELETE requires curl since the CLI lacks a delete subcommand
curl -s -X DELETE "${API_BASE}/v3/notification_subscription/${id}" \
  -H "Authorization: ${REPLICATED_SERVICE_ACCOUNT_TOKEN}" \
  -H "Content-Type: application/json"
```

A hybrid approach works well: use `replicated api get` for reads (it handles auth automatically) and `curl` for DELETE (the one unsupported method).

### Key details

- **API base URL**: `https://api.replicated.com/vendor`
- **Auth header**: `Authorization: ${REPLICATED_SERVICE_ACCOUNT_TOKEN}` (no "Bearer" prefix)
- **curl flags**: `-s` (silent), `-X DELETE` (explicit method)
- Unlike the CLI, `curl` returns nonzero on network failures, making errors detectable

## Prevention

1. **Check `replicated api --help` before using a new HTTP method.** The CLI only supports get/patch/post/put. Any other method requires direct `curl` calls.

2. **Verify the operation succeeded after calling any CLI.** Don't assume exit 0 means the command did what you intended — the `replicated` CLI exits 0 on unrecognized subcommands. Check that the response contains expected data or that state actually changed.

3. **Watch for usage help in stdout.** If a CLI prints "Usage:" or "Available Commands:" instead of API data, treat it as a failure even if exit code is 0.

### Code review checklist

- [ ] `replicated api` method is one of: get, patch, post, put (no delete)
- [ ] DELETE operations use `curl -s -X DELETE` with explicit auth header
- [ ] Script verifies the operation's effect (e.g., re-query to confirm deletion)
- [ ] `REPLICATED_SERVICE_ACCOUNT_TOKEN` is validated with `: "${VAR:?msg}"` before use

## Related Documentation

- `docs/solutions/security-issues/migrate-api-token-from-cmt-to-named-credentials.md` — Token provisioning via `hack/set-api-token` using curl with heredoc stdin
- `docs/solutions/build-errors/makefile-error-suppression-masking-api-failures.md` — Blanket error suppression anti-pattern in Makefile targets calling Replicated API
- `docs/solutions/build-errors/jq-response-shape-mismatch-silent-makefile-target.md` — Related PR #69 finding (jq `.[]` vs `.subscriptions // []`)
- Todo 034 (complete) — curl token in process list; recommends heredoc stdin for sensitive payloads
- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
