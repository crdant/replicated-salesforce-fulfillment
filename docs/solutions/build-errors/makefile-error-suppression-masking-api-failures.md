---
title: Blanket stderr suppression in Makefile target masks real API failures
category: build-errors
date: 2026-03-18
severity: medium
tags:
  - error-handling
  - shell-scripting
  - build-tooling
  - makefile
  - replicated-api
components:
  - Makefile
  - hack/create-license-field
symptoms:
  - Authentication failures appear as "field already exists"
  - Network errors silently reported as "field already exists"
  - No visibility into real causes of entitlements target failures
root_cause: "2>/dev/null || echo suppresses all stderr and treats any non-zero exit as the expected idempotent case, conflating real failures with 409 conflict"
---

# Blanket stderr suppression in Makefile target masks real API failures

## Problem

The `entitlements` Makefile target used `2>/dev/null || echo "Field member_count_max already exists"` to handle the idempotent case where the license field already existed. This suppressed ALL stderr and treated ANY non-zero exit code as "field already exists" — including authentication failures, network timeouts, malformed requests, and permission errors.

A developer with an expired API token would see "Field member_count_max already exists" and believe the field was already created, when the API call never succeeded.

```makefile
# BEFORE — blanket suppression
entitlements:
	@app_id=$$(hack/resolve-app-metadata | jq -r .app_id); \
	replicated api post "/v3/app/$$app_id/license-field" \
	  -b '{"name":"member_count_max","title":"Maximum Members","type":"Integer","default":"100"}' \
	  2>/dev/null || echo "Field member_count_max already exists"
```

Secondary issue: the 4-line inline shell logic broke the project convention of delegating multi-step operations to `hack/` scripts (the same pattern extracted for `channels` → `hack/create-channel` in todo 016).

## Root Cause

The `2>/dev/null || echo` pattern was used as a quick idempotency guard without considering that it catches ALL errors, not just the 409 "already exists" response from the Replicated API. The `||` operator fires on any non-zero exit code, and `2>/dev/null` removes all diagnostic information before the operator can inspect it.

Additionally, if `hack/resolve-app-metadata` failed, `app_id` would be empty, producing a malformed API URL `/v3/app//license-field` — which would also be silently caught by the same `|| echo` fallback.

## Solution

Extracted to `hack/create-license-field` with proper error differentiation:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $0"
    echo ""
    echo "Creates the member_count_max custom license field if it does not already exist."
    echo "Requires REPLICATED_APP and REPLICATED_CHANNEL environment variables."
    exit 1
}

app_id=$("$SCRIPT_DIR/resolve-app-metadata" | jq -r .app_id) || {
    echo "Error: Failed to resolve app metadata. Verify REPLICATED_APP and REPLICATED_CHANNEL are set correctly." >&2
    exit 1
}

output=$(replicated api post "/v3/app/$app_id/license-field" \
  -b '{"name":"member_count_max","title":"Maximum Members","type":"Integer","default":"100"}' \
  2>&1) && {
    echo "Created license field member_count_max"
} || {
    echo "$output" | grep -qiE "already exists|has to be unique" && \
        echo "Field member_count_max already exists" || \
        { echo "Error: Failed to create license field: $output" >&2; exit 1; }
}
```

Makefile simplified to a one-liner delegation:

```makefile
entitlements:
	hack/create-license-field
```

**Key technique:** Capture stderr with `2>&1` into a variable, then inspect the output to distinguish expected 409 ("already exists") from real failures. This replaces the blanket `2>/dev/null` suppression.

## What Changed

| Aspect | Before | After |
|--------|--------|-------|
| Error visibility | All errors hidden | Real errors surface with diagnostics |
| Idempotency | Works but misleading | Works with accurate messaging |
| Script location | Inline in Makefile | `hack/create-license-field` |
| `resolve-app-metadata` failure | Empty `app_id`, malformed URL | Caught by `set -e`, clear error message |
| Convention compliance | Breaks `hack/` pattern | Matches `create-channel`, `set-webhook-secret` |

## Prevention

### When to inline vs. delegate to `hack/`

- **Inline in Makefile:** Single-command targets with no error branching (e.g., `make deploy` → `sf project deploy start ...`)
- **Delegate to `hack/`:** Anything with conditional logic, multi-step operations, or error differentiation

### Idempotent API call pattern

For operations that should succeed whether the resource exists or not:

1. Capture both stdout and stderr: `output=$(command 2>&1)`
2. Check success path first: `&& { echo "Created"; }`
3. On failure, inspect output for the expected error: `grep -qiE "already exists|has to be unique"`
4. If it's the expected error, report idempotent success
5. If it's anything else, surface the real error to stderr and exit non-zero

### Code review checklist for new Makefile targets

- [ ] No blanket `2>/dev/null` — if suppressing stderr, filter by content not by redirection
- [ ] Multi-step logic belongs in a `hack/` script, not inline
- [ ] Error messages distinguish expected states from real failures
- [ ] `hack/` scripts use `set -euo pipefail` and validate prerequisites

## Related

- `docs/solutions/build-errors/makefile-variable-quoting-inconsistency.md` — Makefile quoting conventions
- `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md` — jq `// error()` pattern for nested null detection, applicable to `resolve-app-metadata`
- `docs/solutions/integration-issues/wrong-identifier-type-in-api-call.md` — Verifying API field semantics (`app_id` vs slug)
- PR #65: https://github.com/crdant/replicated-salesforce-fulfillment/pull/65
- PR #48: `hack/create-channel` extraction — same convention pattern
- Todo 016 (complete): Previous extraction of `channels` target to `hack/`
