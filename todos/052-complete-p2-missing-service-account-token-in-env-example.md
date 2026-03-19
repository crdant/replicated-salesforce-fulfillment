---
status: complete
priority: p2
issue_id: "052"
tags:
  - code-review
  - documentation
  - onboarding
dependencies: []
---

# Missing REPLICATED_SERVICE_ACCOUNT_TOKEN in .env.example

## Problem Statement

The `.env.example` file documents environment variables for the project but omits `REPLICATED_SERVICE_ACCOUNT_TOKEN`, which the `credentials` Makefile target requires (`Makefile:15`). This is arguably the most important variable in the project — it powers all outbound Replicated API calls from Salesforce. New contributors following `.env.example` as the canonical source of required variables will miss this critical variable.

## Findings

**File:** `.env.example` — missing `REPLICATED_SERVICE_ACCOUNT_TOKEN`

**Flagged by:** architecture-strategist (Medium), agent-native-reviewer (Critical for agent discoverability)

**Evidence:**
- `Makefile:15`: `hack/set-api-token -o "$(ORG_ALIAS)" -t "${REPLICATED_SERVICE_ACCOUNT_TOKEN}"`
- `README.md:134-138`: Documents setting this variable as a prerequisite
- `.env.example`: Does not include it

## Proposed Solutions

### Option A: Add to .env.example with placeholder
```
# Replicated API authentication (used by `make credentials`)
REPLICATED_SERVICE_ACCOUNT_TOKEN=your-service-account-token-here
```
- **Pros:** `.env.example` becomes complete, single source of truth
- **Cons:** None significant
- **Effort:** Small (1 line)
- **Risk:** Low

### Option B: Add with comment explaining it's separate from setup-replicated
```
# Replicated API authentication (used by `make credentials`, set before `make setup-replicated`)
# Generate at: Vendor Portal > Team > Service Accounts
REPLICATED_SERVICE_ACCOUNT_TOKEN=your-service-account-token-here
```
- **Pros:** Provides provenance hint for where to get the value
- **Cons:** Slightly more verbose
- **Effort:** Small
- **Risk:** Low

## Recommended Action

Option B — include provenance hint so users (and agents) know where to obtain the value.

## Technical Details

**Affected files:**
- `.env.example`

## Acceptance Criteria

- [ ] `REPLICATED_SERVICE_ACCOUNT_TOKEN` appears in `.env.example`
- [ ] Every variable referenced by Makefile targets has an entry in `.env.example`

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-19 | Created from PR #70 code review | .env.example should be single source of truth for all env vars |

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
