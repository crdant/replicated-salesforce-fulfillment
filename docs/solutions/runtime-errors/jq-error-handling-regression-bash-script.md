---
title: jq error handling regression when simplifying bash script pipeline
category: runtime-errors
severity: medium
date: 2026-03-18
tags:
  - bash
  - jq
  - error-handling
  - shell-scripts
  - code-review
modules:
  - hack/resolve-app-metadata
  - hack/import
symptoms:
  - Non-existent app produces raw jq error "Cannot iterate over null"
  - Non-existent channel silently returns channel_id null with exit code 0
  - jq -e flag only catches top-level null/false, not nested null fields
---

# jq error handling regression when simplifying bash script pipeline

## Problem

PR #49 extracted a Replicated app metadata lookup from `hack/import:48` into a reusable `hack/resolve-app-metadata` script. Code review identified the original 40-line three-pass jq approach was over-engineered. When simplified to a single-pass jq pipeline, the test plan revealed two silent failures:

1. **App not found**: `[...] | first` returns `null` → piped to `.channels[]` → raw jq error "Cannot iterate over null (null)"
2. **Channel not found**: `[...] | first` returns `null` → embedded in output as `"channel_id": null` with exit code 0

Both went undetected because `jq -e` only validates whether the top-level output is `null` or `false`. Nested null values pass through silently.

## Root Cause

jq's `first` function returns `null` when applied to an empty array. The `// (alternative)` operator in jq treats `null` as falsy, but `first` does not raise an error — it quietly produces `null`. When that null is embedded inside an object (`{ channel_id: null }`), `jq -e` considers the top-level output (the object) to be truthy and exits 0.

The three-pass approach had explicit `-z` checks on intermediate shell variables that caught these cases. The single-pass simplification removed those checkpoints without replacing them with jq-native equivalents.

## Solution

Use jq's `// error("message")` pattern to explicitly validate at each critical lookup point:

```bash
replicated app ls --output json | jq -e --arg app "$REPLICATED_APP" --arg channel "$REPLICATED_CHANNEL" \
  '  [.[] | select(.app.slug == $app)] | first
     // error("App \($app) not found")
   | {
       app_name: .app.name,
       app_id: .app.id,
       channel_id: ([.channels[] | select(.channelSlug == $channel) | .id] | first
                    // error("Channel \($channel) not found for app \($app)"))
     }'
```

The `// error(...)` pattern:
- Catches `null` from `first` on no-match cases (since `null` is falsy for `//`)
- Provides context-specific error messages with variable interpolation via `\(...)`
- Terminates the entire jq pipeline with a non-zero exit code
- Works at any nesting depth, unlike `jq -e` which only checks the top level

### Additional changes in the same PR

- **Env var validation**: Replaced 10-line `if/echo/exit` blocks with 2-line `:?` parameter expansion:
  ```bash
  : "${REPLICATED_APP:?REPLICATED_APP is not set}"
  : "${REPLICATED_CHANNEL:?REPLICATED_CHANNEL is not set}"
  ```
- **Consumer wiring**: Updated `hack/import` to call `resolve-app-metadata` instead of inline jq, removing dead `-a`/`-c` getopts
- **Discoverability**: Added script to CLAUDE.md "Utility Scripts" section

## Key Code Changes

| File | Change |
|------|--------|
| `hack/resolve-app-metadata` | Collapsed from 40 to 18 lines; single-pass jq with `// error()` guards |
| `hack/import` | Replaced inline jq (line 48) with call to `resolve-app-metadata`; removed dead `-a`/`-c` flags |
| `CLAUDE.md` | Added Utility Scripts section documenting `resolve-app-metadata` |

## Prevention Checklist

- [ ] When simplifying multi-step pipelines to single-pass, test every error path the original handled
- [ ] Never rely on `jq -e` alone for nested null detection — use `// error("message")` at each lookup stage
- [ ] Test jq filters with empty arrays: `echo '[]' | jq 'your-filter'`
- [ ] When extracting shared utilities, update all consumers in the same PR — zero-consumer scripts are dead code
- [ ] Add new `hack/` scripts to CLAUDE.md for discoverability

## Testing Guidelines

Run all 5 test cases for any script that resolves external data:

```bash
# 1. Happy path
REPLICATED_APP=valid-app REPLICATED_CHANNEL=valid-channel hack/resolve-app-metadata

# 2-3. Missing env vars (use env -u to truly unset)
env -u REPLICATED_APP hack/resolve-app-metadata
env -u REPLICATED_CHANNEL REPLICATED_APP=valid-app hack/resolve-app-metadata

# 4-5. Non-existent values
REPLICATED_APP=no-such-app REPLICATED_CHANNEL=valid-channel hack/resolve-app-metadata
REPLICATED_APP=valid-app REPLICATED_CHANNEL=no-such-channel hack/resolve-app-metadata
```

**Gotcha**: Running `unset VAR && VAR2=x script` in a single shell command does not isolate the unset — use `env -u VAR` to guarantee the variable is absent from the child process.

## Related Documentation

- [Incomplete CMT Object Rename](../workflow/incomplete-cmt-object-rename-in-docs.md) — Same pattern of incomplete refactoring across file layers
- [Wrong Identifier Type in API Call](../integration-issues/wrong-identifier-type-in-api-call.md) — Incomplete data extraction causing downstream bugs
- [Salesforce Webhook Endpoint Testing](../integration-issues/salesforce-webhook-endpoint-testing-integration.md) — Related `hack/` script issues including non-existent CLI commands
- PR #49, Issue #41
