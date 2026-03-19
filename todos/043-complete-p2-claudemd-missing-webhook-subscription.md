---
status: complete
priority: p2
issue_id: "043"
tags:
  - code-review
  - documentation
  - agent-native
dependencies: []
---

# Document webhook-subscription in CLAUDE.md

## Problem Statement

The new `make webhook-subscription` target and `hack/setup-webhook-subscription` script are not documented in CLAUDE.md. Every other Makefile target (`deploy`, `retrieve`, `credentials`, `import`, `clean`) is listed, but `webhook-subscription` and `channels` are both missing. An agent working in this project will not discover these capabilities without exploring the Makefile. Past learnings (`docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md`) explicitly state: "Always add new `hack/` scripts to CLAUDE.md for discoverability."

## Findings

**CLAUDE.md** "Common Commands" section (lines 22-28) — missing `make webhook-subscription` and `make channels`

**CLAUDE.md** "Utility Scripts" section (lines 30-32) — missing `hack/setup-webhook-subscription`

The required environment variables (`REPLICATED_SITE_URL`, `REPLICATED_WEBHOOK_SECRET`) are also undocumented. The meaning of `REPLICATED_SITE_URL` is ambiguous — it could refer to the Salesforce site webhook endpoint or a Replicated URL.

## Proposed Solutions

### Option A: Add to both sections (Recommended)
- Add `make webhook-subscription` to Common Commands
- Add `make channels` to Common Commands (also missing)
- Add `hack/setup-webhook-subscription` to Utility Scripts with env var descriptions
- **Effort**: Small
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `make webhook-subscription` listed in CLAUDE.md Common Commands
- [ ] `make channels` listed in CLAUDE.md Common Commands
- [ ] `hack/setup-webhook-subscription` listed in Utility Scripts with required env vars
- [ ] `REPLICATED_SITE_URL` purpose clarified (webhook callback URL for the Salesforce site)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #67 code review — matches known pattern from past learnings | Past solution explicitly calls out adding hack/ scripts to CLAUDE.md |

## Resources

- PR: https://github.com/crdant/replicated-salesforce-fulfillment/pull/67
- Known pattern: `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md`
- CLAUDE.md: project root
