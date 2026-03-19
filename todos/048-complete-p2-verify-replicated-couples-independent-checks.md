---
status: complete
priority: p2
issue_id: "048"
tags:
  - code-review
  - architecture
  - simplicity
dependencies: []
---

# verify-replicated couples independent checks via unnecessary dependency

## Problem Statement

`verify-replicated` depends on `verify-webhook`, meaning you cannot verify app/channel metadata without also sending a test webhook. These are independent operations — verifying the Replicated app and channel exist has nothing to do with whether the webhook endpoint is reachable. The coupling forces both to run together and means `verify-replicated` fails when the webhook test fails, even when you only care about app metadata.

Additionally, the two targets require different env vars (`REPLICATED_SITE_URL`/`REPLICATED_WEBHOOK_SECRET` vs `REPLICATED_APP`/`REPLICATED_CHANNEL`), making the full requirement non-obvious.

## Findings

**File:** `Makefile:33` — `verify-replicated: verify-webhook`

**Flagged by:**
- Simplicity reviewer: "Coupling them forces both to run together... each target should do exactly one thing"
- Agent-native reviewer: "Running `make verify-replicated` with only REPLICATED_APP and REPLICATED_CHANNEL set would get a non-obvious failure from the webhook test"

## Proposed Solutions

### Option A: Decouple and add composite target
```makefile
verify-webhook:
	hack/test-webhook -u "${REPLICATED_SITE_URL}" -s "${REPLICATED_WEBHOOK_SECRET}"

verify-replicated:
	@hack/resolve-app-metadata > /dev/null && echo "Channel and app verified."

verify: verify-webhook verify-replicated
```
- **Effort**: Small
- **Risk**: Low
- **Pros**: Each target has single responsibility, composite target for full verification
- **Cons**: Adds one target

### Option B: Keep coupled but document env var requirements
- Add comments documenting all required env vars.
- **Effort**: Small
- **Risk**: Low
- **Pros**: No structural change
- **Cons**: Coupling remains; doesn't fix the actual issue

## Recommended Action

Option A — decouple targets, add `verify` composite.

## Technical Details

**Affected files:**
- `Makefile` — Lines 33-34

## Acceptance Criteria

- [ ] `make verify-replicated` succeeds with only `REPLICATED_APP` and `REPLICATED_CHANNEL` set
- [ ] `make verify-webhook` succeeds with only `REPLICATED_SITE_URL` and `REPLICATED_WEBHOOK_SECRET` set
- [ ] `make verify` runs both checks

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #69 code review | Single-responsibility applies to Makefile targets too |

## Resources

- PR #69: https://github.com/crdant/replicated-salesforce-fulfillment/pull/69
