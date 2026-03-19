---
title: Unquoted Make variables break with user-supplied ORG_ALIAS values
category: build-errors
date: 2026-03-18
severity: medium
components:
  - Makefile
  - Deployment tooling
tags:
  - makefile
  - shell-quoting
  - org-configuration
  - variable-expansion
related_issues:
  - 38
  - 53
  - 55
---

# Unquoted Make variables break with user-supplied ORG_ALIAS values

## Problem

When PR #53 replaced hardcoded `shortrib` org aliases with a configurable `ORG_ALIAS ?= shortrib` variable, three of six Makefile targets used unquoted `$(ORG_ALIAS)` while the other three quoted it. The default value `shortrib` masked the problem — but any override containing spaces or shell metacharacters would break the unquoted targets.

**Symptom:** `make deploy ORG_ALIAS="my org"` fails on unquoted targets with argument parsing errors, while quoted targets work correctly.

## Root Cause

Make expands `$(ORG_ALIAS)` before the shell sees the recipe. Without quotes, the shell applies word-splitting and pathname expansion to the expanded value. The unquoted form:

```makefile
sf project deploy start --manifest package.xml -o $(ORG_ALIAS)
```

becomes this in the shell when `ORG_ALIAS="my org"`:

```bash
sf project deploy start --manifest package.xml -o my org
#                                                    ^ word-split into separate argument
```

The quoted form `"$(ORG_ALIAS)"` preserves the value as a single argument.

**Before (inconsistent):**

| Target | Quoting | Safe? |
|--------|---------|-------|
| `deploy` | `$(ORG_ALIAS)` | No |
| `retrieve` | `$(ORG_ALIAS)` | No |
| `webhook-secret` | `$(ORG_ALIAS)` | No |
| `credentials` | `"$(ORG_ALIAS)"` | Yes |
| `clean` | `"$(ORG_ALIAS)"` | Yes |
| `import` | `"$(ORG_ALIAS)"` | Yes |

## Solution

Quote all `$(ORG_ALIAS)` references consistently (commit ba3cc24):

```diff
 deploy:
-	sf project deploy start --manifest package.xml -o $(ORG_ALIAS)
+	sf project deploy start --manifest package.xml -o "$(ORG_ALIAS)"

 retrieve:
-	sf project retrieve start --manifest package.xml -o $(ORG_ALIAS)
+	sf project retrieve start --manifest package.xml -o "$(ORG_ALIAS)"

 webhook-secret:
-	hack/set-webhook-secret -o $(ORG_ALIAS) -s "${REPLICATED_WEBHOOK_SECRET}"
+	hack/set-webhook-secret -o "$(ORG_ALIAS)" -s "${REPLICATED_WEBHOOK_SECRET}"
```

All six targets now use `"$(ORG_ALIAS)"`.

## Key Insight: Make vs. Shell Variable Syntax

In Makefile recipes, both `$(VAR)` and `${VAR}` are Make variable references — Make expands them before passing the recipe to the shell. The `${VAR}` syntax does **not** mean "shell variable" inside a recipe (use `$${VAR}` for that).

When a Make variable is user-configurable, always quote its expansion in recipes: `"$(VAR)"`. This prevents shell word-splitting regardless of the variable's content.

## Prevention

### Makefile variable introduction checklist

1. Define at top of Makefile with `?=` (allows environment/command-line override)
2. Use `$(VAR)` syntax consistently (not `${VAR}`) to visually distinguish from shell env vars
3. Always quote in recipes: `"$(VAR)"`
4. Verify consistency: `grep -n '$(VAR_NAME)' Makefile` — all occurrences should be quoted
5. Test with edge-case overrides before committing: `VAR="val with spaces" make target`

### Convention

When the default value works without quotes (e.g., `shortrib` has no spaces), the bug is invisible. Always quote defensively — the cost is zero and it prevents future breakage.

## Related

- [Salesforce webhook endpoint testing](../integration-issues/salesforce-webhook-endpoint-testing-integration.md) — documents the original org alias inconsistency and recommends the `?=` pattern
- [Incomplete CMT object rename](../workflow/incomplete-cmt-object-rename-in-docs.md) — checklist for variable/identifier renames across the codebase
- Issue #38 — original request to replace hardcoded org alias
- Issue #55 — add `.PHONY` declarations (related Makefile hardening)
