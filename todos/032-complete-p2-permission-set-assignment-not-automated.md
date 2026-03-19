---
status: complete
priority: p2
issue_id: "032"
tags:
  - code-review
  - agent-accessibility
  - tooling
dependencies: []
---

# Automate Permission Set assignment in setup workflow

## Problem Statement

The `Replicated_API_Access` Permission Set is deployed with the metadata but never assigned. Without it, callouts via the Named Credential fail with a generic authorization error. Neither the README, Makefile, nor `hack/set-api-token` script handles assignment. This is the only gap preventing an agent from going zero-to-working-integration in one pass.

## Findings

- **Source**: agent-native-reviewer, architecture-strategist
- **File**: `Makefile` (missing target), `README.md` (missing step between deploy and credentials)
- The Permission Set gates access to `Replicated_Vendor_Portal.NamedPrincipal`
- After `make deploy` + `make credentials`, the running user still cannot invoke the Named Credential without this assignment
- Salesforce error message is a generic "unauthorized endpoint" — not helpful for debugging

## Proposed Solutions

### Option A: Add a Makefile target
- Add `make permissions` target: `sf org assign permset --name Replicated_API_Access --target-org shortrib`
- Add step to README between deploy and credentials
- **Effort**: Small
- **Risk**: Low
- **Pros**: Follows existing pattern of separate Makefile targets
- **Cons**: Extra manual step to remember

### Option B: Fold into `make deploy` as post-deploy step
- Add `sf org assign permset` after `sf project deploy start` in the deploy target
- **Effort**: Small
- **Risk**: Low — idempotent operation
- **Pros**: One fewer step; permission is always assigned after deploy
- **Cons**: Couples deployment with permission assignment

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Running user has `Replicated_API_Access` assigned after setup workflow
- [ ] README documents the permission set requirement
- [ ] An agent can run the full setup (deploy → permissions → credentials) without manual steps

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #54 code review | Only functional gap in agent-native parity |

## Resources

- PR #54: Named Credentials migration
- `create-license/main/default/permissionsets/Replicated_API_Access.permissionset-meta.xml`
