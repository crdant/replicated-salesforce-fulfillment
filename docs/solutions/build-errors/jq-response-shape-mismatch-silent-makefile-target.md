---
title: "jq response shape mismatch makes Makefile cleanup target silently non-functional"
category: "build-errors"
date: 2026-03-19
tags:
  - makefile
  - replicated-api
  - jq-parsing
  - script-extraction
  - error-handling
  - stderr-suppression
severity: "critical"
components:
  - "Makefile"
  - "hack/clean-webhook-subscription"
  - "hack/setup-webhook-subscription"
  - "Replicated API integration"
related_todos:
  - 040
  - 041
  - 045
  - 046
  - 047
  - 048
  - 049
---

# jq response shape mismatch makes Makefile cleanup target silently non-functional

## Problem

The `replicated-clean` Makefile target used `.[]` to iterate the Replicated API response from `/v3/notification_subscriptions`. The API returns `{"subscriptions": [...]}`, not a bare array. Using `.[]` on the object iterates its keys (producing the string `"subscriptions"`), so `select(.name == "Salesforce CRM Sync")` never matches and the target silently deletes nothing.

Combined with `2>/dev/null` suppressing all stderr, the target appeared to succeed while doing nothing.

**Symptoms:**
- `make replicated-clean` prints "Removing webhook subscription..." then exits silently with no error
- Webhook subscription remains in the Replicated Vendor Portal after running the target
- No error output because `2>/dev/null` suppresses API and jq failures

## Root Cause

The jq expression `.[]` applied to `{"subscriptions": [...]}` iterates object keys, not array elements. The correct expression is `.subscriptions // [] | .[]`, which first extracts the nested array then iterates it.

The existing `hack/setup-webhook-subscription` (line 13-15) already used the correct form:

```bash
existing=$(replicated api get /v3/notification_subscriptions | \
  jq -e --arg name "$SUBSCRIPTION_NAME" \
    '.subscriptions // [] | map(select(.name == $name)) | first // empty' 2>/dev/null) || true
```

The new Makefile target was written inline without referencing this established pattern, and `2>/dev/null` masked the resulting silent failure.

**Secondary issues found in the same PR:**
- Inline multi-step logic in the Makefile broke the project's delegation-to-`hack/` convention
- `verify-replicated: verify-webhook` coupled two independent verification checks
- `verify-replicated` discarded useful JSON output with `> /dev/null`

## Solution

### 1. Extracted to `hack/clean-webhook-subscription` with correct jq

```bash
#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_NAME="Salesforce CRM Sync"

echo "Checking for webhook subscriptions to remove..."
response=$(replicated api get /v3/notification_subscriptions)

ids=$(echo "$response" | jq -r --arg name "$SUBSCRIPTION_NAME" \
  '.subscriptions // [] | .[] | select(.name == $name) | .id')

if [ -z "$ids" ]; then
    echo "No subscription named \"${SUBSCRIPTION_NAME}\" found."
    exit 0
fi

echo "$ids" | while read -r id; do
    echo "Deleting subscription ${id}..."
    replicated api delete "/v3/notification_subscription/${id}"
done

echo "Done."
```

Key fixes:
- `.subscriptions // [] | .[]` correctly accesses the nested array
- `set -euo pipefail` surfaces real errors instead of `2>/dev/null` hiding them
- Explicit "not found" message distinguishes empty results from API failures
- Follows the project's delegation pattern (all targets call `hack/` scripts)

### 2. Simplified Makefile targets

```makefile
verify-webhook:
	hack/test-webhook -u "${REPLICATED_SITE_URL}" -s "${REPLICATED_WEBHOOK_SECRET}"

verify-replicated:
	@hack/resolve-app-metadata

verify: verify-webhook verify-replicated

replicated-clean:
	hack/clean-webhook-subscription
```

Key fixes:
- `verify-replicated` decoupled from `verify-webhook` (independent checks, different env vars)
- Composite `verify` target runs both when needed
- `verify-replicated` shows resolved JSON output instead of discarding it
- `replicated-clean` delegates to the new script

### Investigation

The agent-native reviewer caught the jq mismatch by cross-referencing the Makefile expression against `hack/setup-webhook-subscription`. The learnings researcher surfaced two documented anti-patterns (stderr suppression from todo 040, inline logic from todo 041) that matched findings in this PR. Five review agents were run in parallel; three flagged the inline logic, two flagged the stderr suppression, and one identified the response shape bug.

## Prevention

1. **Reference existing scripts when writing new jq expressions for the same API.** The correct `.subscriptions // []` pattern already existed in `hack/setup-webhook-subscription`. Inline Makefile logic bypassed this established pattern.

2. **Never use blanket `2>/dev/null` on API calls.** This is the third time this anti-pattern has appeared in this project (see todos 040, 041). Let stderr flow through; use `set -euo pipefail` in scripts to catch real failures.

3. **Keep multi-step logic in `hack/` scripts.** The Makefile is a thin orchestration layer. Inline pipelines (API call + jq + while loop) belong in scripts where they get `set -euo pipefail`, proper error handling, and testability.

4. **Decouple independent Make targets.** If two checks require different env vars and serve different purposes, don't chain them with prerequisites. Create a composite target instead.

### Code Review Checklist

- [ ] jq expressions match the documented API response shape (check existing scripts for the same endpoint)
- [ ] No blanket `2>/dev/null` on API calls without justification
- [ ] Multi-step logic delegates to `hack/` scripts, not inline in Makefile
- [ ] Destructive targets provide feedback on what was deleted (or that nothing was found)
- [ ] Make targets with prerequisites actually need the dependency (independent checks should be independent targets)
- [ ] String constants (e.g., subscription names) are not duplicated across files

## Related Documentation

- `docs/solutions/build-errors/makefile-error-suppression-masking-api-failures.md` — Blanket `2>/dev/null` anti-pattern (same root cause for the suppression issue)
- `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md` — jq `// error()` pattern for nested null detection
- `docs/solutions/build-errors/makefile-variable-quoting-inconsistency.md` — Makefile quoting conventions
- Todo 040 (complete) — First `2>/dev/null` suppression fix (entitlements target)
- Todo 041 (complete) — First inline-to-script extraction (entitlements target)
- Todo 016 (complete) — channels target extraction to `hack/create-channel`
- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
