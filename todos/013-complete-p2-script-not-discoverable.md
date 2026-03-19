---
status: complete
priority: p2
issue_id: "013"
tags:
  - code-review
  - architecture
  - documentation
dependencies: []
---

# Add hack/resolve-app-metadata to CLAUDE.md and Makefile

## Problem Statement

`hack/resolve-app-metadata` is not referenced in CLAUDE.md or the Makefile. Every other operational script in `hack/` (`clean`, `import`, `set-webhook-secret`) has a Makefile target and is documented in CLAUDE.md. Without discoverability, neither developers nor AI agents will know this utility exists.

## Findings

**Agent-Native Reviewer:** Discoverability FAIL — script not referenced in CLAUDE.md, Makefile, or any other script. An agent asked to "look up the app ID for a Replicated app" would not know this tool exists.

**Learnings Researcher:** Past solution `docs/solutions/security-issues/webhook-receiver-code-review-findings.md` establishes that "every configuration step needs a CLI path" and `hack/` scripts should have Makefile targets for discoverability.

**Architecture Strategist:** Any callers invoking by relative path (`hack/resolve-app-metadata`) must run from the project root. This is true of all Makefile targets but worth documenting.

## Proposed Solutions

### Option A: Add to CLAUDE.md only (Recommended)
- Add entry to the "Common Commands" section documenting purpose, env var inputs, and JSON output schema
- This is a lower-level utility called by other scripts, so a Makefile target may not be necessary
- **Effort**: Small
- **Risk**: None

### Option B: Add to both CLAUDE.md and Makefile
- Add CLAUDE.md documentation
- Add a `metadata` or `resolve-metadata` Makefile target
- Full parity with other `hack/` scripts
- **Effort**: Small
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `hack/resolve-app-metadata` documented in CLAUDE.md with env var inputs and output schema
- [ ] An agent reading CLAUDE.md can discover and invoke the script

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #49 code review | Project convention: hack/ scripts should be discoverable via CLAUDE.md or Makefile |

## Resources

- PR: #49
- File: `CLAUDE.md`
- File: `Makefile`
- Past solution: `docs/solutions/security-issues/webhook-receiver-code-review-findings.md`
