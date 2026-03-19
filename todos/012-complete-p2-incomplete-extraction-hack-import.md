---
status: complete
priority: p2
issue_id: "012"
tags:
  - code-review
  - architecture
  - shell
dependencies: []
---

# Refactor hack/import to consume hack/resolve-app-metadata

## Problem Statement

PR #49 extracts the Replicated app metadata lookup into `hack/resolve-app-metadata` but does not update `hack/import` (line 48) to use it. This leaves two independent implementations of the same logic: the original inline `jq` one-liner and the new 40-line script. The "shared" script is shared by nothing — zero consumers exist.

This undermines the stated goal (issue #41) of eliminating duplication and creates divergence risk if the Replicated API response structure changes.

## Findings

**Architecture Strategist:** The extraction is sound, but the PR is incomplete without updating `hack/import`. Two code paths resolve the same metadata with subtly different jq filters.

**Code Simplicity Reviewer:** YAGNI violation — extracting a shared utility before there is a second consumer. `grep` for `resolve-app-metadata` returns zero results across the entire repo.

**Agent-Native Reviewer:** An agent would find two independent implementations doing the same thing, creating confusion about which is canonical.

**Learnings Researcher:** Past solution `docs/solutions/workflow/incomplete-cmt-object-rename-in-docs.md` documents a pattern of incomplete renames where `hack/` scripts were missed.

**Additional note:** `hack/import` has dead `-a` and `-c` getopts cases (lines 9-11) — the `-a` flag sets `APPLICATION` but line 48 reads `$REPLICATED_APP`, which is never set from the flag. These should be cleaned up when refactoring.

## Proposed Solutions

### Option A: Update hack/import in this PR (Recommended)
- Replace `hack/import` lines 48-51 with a call to `hack/resolve-app-metadata`
- Remove dead `-a` and `-c` getopts cases
- Validates the "shared" claim before merging
- **Effort**: Small
- **Risk**: Low — functional behavior is unchanged

```bash
metadata=$(hack/resolve-app-metadata)
app_name=$(echo "$metadata" | jq -r .app_name)
app_id=$(echo "$metadata" | jq -r .app_id)
channel_id=$(echo "$metadata" | jq -r .channel_id)
```

### Option B: Create a follow-up issue
- Track the `hack/import` migration as a separate issue
- Merge the utility script now, refactor later
- Risk: the follow-up is deprioritized and duplication persists
- **Effort**: Small (issue creation)
- **Risk**: Medium — incomplete refactoring tends to be forgotten

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `hack/import` calls `hack/resolve-app-metadata` instead of inline jq
- [ ] Dead `-a` and `-c` getopts cases removed from `hack/import`
- [ ] `hack/resolve-app-metadata` has at least one consumer
- [ ] Both scripts produce identical metadata for the same inputs

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #49 code review | Past pattern of incomplete extractions documented in docs/solutions/ |

## Resources

- PR: #49
- Issue: #41
- File: `hack/import` (lines 48-51)
- File: `hack/resolve-app-metadata`
- Past solution: `docs/solutions/workflow/incomplete-cmt-object-rename-in-docs.md`
