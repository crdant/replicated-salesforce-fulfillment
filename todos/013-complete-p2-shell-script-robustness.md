---
status: complete
priority: p2
issue_id: "013"
tags:
  - code-review
  - tooling
  - security
dependencies: []
---

# Harden hack/set-api-token shell script

## Problem Statement

The `hack/set-api-token` script lacks defensive shell options and makes a redundant CLI call. Without `set -euo pipefail`, failures in the `sf org display | jq` pipeline can pass silently. The script also calls `sf org display` twice for the same org, extracting different fields each time.

## Findings

- **Source**: security-sentinel, architecture-strategist, code-simplicity-reviewer
- **File**: `hack/set-api-token`, lines 1, 40-41
- Missing `set -euo pipefail` after shebang — pipeline failures may pass silently
- Lines 40-41 call `sf org display --target-org "$ORG_ALIAS" --json` twice — redundant network call
- Existing null checks (lines 43-51) partially mitigate but don't fully cover pipeline failure modes

## Proposed Solutions

### Option A: Add defensive options and consolidate
- Add `set -euo pipefail` after shebang
- Store `sf org display` JSON in a variable, extract both fields from it
- **Effort**: Small (3-line change)
- **Risk**: Low
- **Pros**: Standard shell best practice; faster execution
- **Cons**: None

```bash
#!/usr/bin/env bash
set -euo pipefail

# ... later:
ORG_INFO=$(sf org display --target-org "$ORG_ALIAS" --json)
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')
```

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Script has `set -euo pipefail` after shebang
- [ ] `sf org display` called only once
- [ ] Script still handles all error cases correctly

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #54 code review | Consistent with shell scripting best practices |

## Resources

- PR #54: Named Credentials migration
- `hack/set-api-token`: lines 1, 40-41
- `hack/set-webhook-secret`: sibling script for comparison
