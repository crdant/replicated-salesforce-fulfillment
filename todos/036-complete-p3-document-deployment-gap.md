---
status: complete
priority: p3
issue_id: "036"
tags:
  - code-review
  - documentation
dependencies: []
---

# Document deployment gap between deploy and credentials

## Problem Statement

After `make deploy` but before `make credentials`, the Named Credential exists without a token. Any Order activation during this window triggers a `ReplicatedFulfillment` callout that fails. This is inherent to the Named Credential approach (secret values cannot be deployed via Metadata API) but should be documented.

## Findings

- **Source**: architecture-strategist
- **File**: `README.md` (setup section)
- The test plan correctly sequences deploy → credentials, but neither README nor a deployment runbook calls out the failure window
- For production environments, this window would need coordination during a maintenance window

## Proposed Solutions

### Option A: Add a note to README setup section
- Brief callout between deploy and credentials steps
- **Effort**: Small
- **Risk**: None

### Option B: No action needed
- The test plan already sequences the steps correctly
- This is a dev/demo environment with controlled deployments
- **Effort**: None
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] README acknowledges that credentials must be set immediately after deploy

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #54 code review | Operational awareness for production deployments |

## Resources

- PR #54: Named Credentials migration
- `README.md`: setup section, steps 3-5
