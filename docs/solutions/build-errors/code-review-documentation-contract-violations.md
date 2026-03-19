---
title: "Documentation-code contract violations and onboarding gaps in orchestrator PR"
category: "build-errors"
date: "2026-03-19"
severity: "high"
tags:
  - documentation
  - makefile
  - onboarding
  - environment-configuration
  - build-automation
  - code-review
affected_components:
  - Makefile
  - README.md
  - .env.example
  - CLAUDE.md
  - hack/create-channel
symptoms:
  - README references non-existent Makefile targets (`verify-replicated`, `replicated-clean`)
  - Make prerequisites don't guarantee execution order with `make -j`
  - Critical environment variable omitted from `.env.example`
  - New Makefile target not discoverable by agents via CLAUDE.md
  - Inconsistent shell hardening across hack/ scripts
  - Placeholder values in `.env.example` give no hint where to obtain real values
root_cause: "Insufficient validation of documentation against actual implementation, misunderstanding of Make prerequisite semantics, and incomplete enumeration of environment variables during setup documentation."
---

# Documentation-Code Contract Violations in Orchestrator PR

## Problem Statement

PR #70 added a `make setup-replicated` orchestrator target, `.env.example`, and README documentation. Code review found 6 issues where documentation promised things the code couldn't deliver, Makefile semantics were subtly wrong, and onboarding documentation was incomplete. One issue (phantom targets) was P1; three were P2; two were P3.

## Root Cause

Six distinct failure modes, all rooted in documentation-implementation drift:

1. **Phantom Makefile targets**: README steps 3-4 documented `make verify-replicated` and `make replicated-clean` but neither target existed in the Makefile. Users following the README would hit `make: *** No rule to make target` errors.

2. **Make prerequisite ordering assumption**: `setup-replicated: channels enterprise-portal entitlements webhook-subscription` uses Make prerequisites, which are a dependency *set*, not an ordered sequence. GNU Make processes them left-to-right in single-job mode by convention, but `make -j` runs them in parallel. There's a real dependency: `enterprise-portal` and `entitlements` call `hack/resolve-app-metadata`, which queries for the channel created by `channels`.

3. **Missing critical environment variable**: `.env.example` omitted `REPLICATED_SERVICE_ACCOUNT_TOKEN`, required by `make credentials` (Makefile line 15). This is the API token powering all outbound Replicated calls.

4. **CLAUDE.md not updated**: New `make setup-replicated` target wasn't in CLAUDE.md Common Commands. Same class of issue as prior todo #043.

5. **Inconsistent shell hardening**: `hack/create-channel` was the only `hack/` script without `set -euo pipefail`.

6. **No provenance hints**: `.env.example` placeholders like `your-app-slug` gave no guidance on where to obtain real values.

## Solution

### Fix 1: Remove phantom targets from README

Deleted steps 3-4 from the "Replicated Platform Setup" section. Documenting unimplemented features is a YAGNI violation.

### Fix 2: Use explicit `$(MAKE)` recipe calls

Changed from prerequisite syntax to ordered recipe calls, guaranteeing sequential execution regardless of `-j` flags:

```makefile
# Before (ordering not guaranteed with make -j):
setup-replicated: channels enterprise-portal entitlements webhook-subscription

# After (sequential execution guaranteed):
setup-replicated:
	$(MAKE) channels
	$(MAKE) enterprise-portal
	$(MAKE) entitlements
	$(MAKE) webhook-subscription
```

Updated README wording from "dependency order" to "in sequence" to accurately describe the behavior.

### Fix 3: Add missing env var to `.env.example`

```bash
# Replicated API authentication (used by `make credentials`)
# Generate at: Vendor Portal > Team > Service Accounts
REPLICATED_SERVICE_ACCOUNT_TOKEN=your-service-account-token-here
```

### Fix 4: Add `setup-replicated` to CLAUDE.md

```bash
make setup-replicated      # Configure all Replicated Platform resources (channels, portal, entitlements, webhooks)
```

### Fix 5: Add strict mode to `hack/create-channel`

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Fix 6: Add provenance hints to `.env.example`

```bash
# Replicated app configuration (from `replicated app ls` or Vendor Portal > Settings)
REPLICATED_APP=your-app-slug

# Generate secret with: openssl rand -hex 32
REPLICATED_WEBHOOK_SECRET=your-webhook-secret-here

# Salesforce Site webhook URL (available after Site is created and activated)
REPLICATED_SITE_URL=https://your-site-domain/services/apexrest/replicated/webhook
```

## Prevention Strategies

### Review Checklist for Makefile/Documentation PRs

- [ ] Every `make` target referenced in README exists in the Makefile (`grep -oP 'make \K[a-z-]+' README.md` vs `grep -E '^[a-z-]+:' Makefile`)
- [ ] New Makefile targets added to CLAUDE.md Common Commands
- [ ] Every env var used by Makefile targets has an entry in `.env.example`
- [ ] Orchestrator targets use `$(MAKE)` recipe calls, not prerequisites, when order matters
- [ ] All `hack/` scripts include `set -euo pipefail`
- [ ] `.env.example` placeholders include provenance comments (where to obtain the value)

### Patterns to Watch For

1. **Documentation lag on Makefile changes** -- CLAUDE.md treated as separate from code; no automated sync. This is a recurring pattern (todo #043 was identical).

2. **Ordering assumptions in phony targets** -- Make prerequisites are sets, not sequences. Any target where sub-targets have real dependencies must use `$(MAKE)` recipe calls.

3. **Environment variable creep** -- Developers add vars to scripts without updating `.env.example`. The example file should be the single source of truth for all env vars.

4. **Inconsistent shell script idioms** -- Without a template or linting, scripts inherit varying quality. Enforce `set -euo pipefail` across all `hack/` scripts.

## Related Documentation

- `docs/solutions/build-errors/makefile-error-suppression-masking-api-failures.md` -- Makefile error handling patterns, convention of delegating multi-step logic to `hack/` scripts
- `docs/solutions/build-errors/makefile-variable-quoting-inconsistency.md` -- Makefile variable introduction checklist, quoting patterns
- `docs/solutions/runtime-errors/jq-error-handling-regression-bash-script.md` -- Shell script hardening, `:?` parameter expansion, CLAUDE.md discoverability for new scripts
- `docs/solutions/workflow/incomplete-cmt-object-rename-in-docs.md` -- Documentation-code consistency verification via `git grep`
- `docs/solutions/security-issues/webhook-receiver-code-review-findings.md` -- Multi-agent code review findings, operational friction from phantom targets

## Resources

- PR #70: https://github.com/crdant/replicated-salesforce-fulfillment/pull/70
- Issue #47: Setup orchestrator and env documentation
- Todo files: `todos/050-055` (all complete)
- Prior related todo: #043 (CLAUDE.md missing webhook-subscription)
