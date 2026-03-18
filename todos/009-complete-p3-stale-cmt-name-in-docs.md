---
status: complete
priority: p3
issue_id: "009"
tags:
  - code-review
  - documentation
  - consistency
dependencies: []
---

# Update stale CMT name references in docs

## Problem Statement

The PR renames `ReplicatedVendorPortalCredential__mdt` to `Replicated_Vendor_Portal_API_Credential__mdt` in all Apex code and primary docs, but 4 references to the old name remain in research and solutions documents. These docs already use the new name elsewhere, creating internal inconsistencies.

## Findings

1. `docs/research/2026-03-16-secret-storage-evaluation.md:70` — refactoring instruction still references old name
2. `docs/research/2026-03-16-secret-storage-evaluation.md:175` — "Before" code snippet uses old name
3. `docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md:49` — "Before" SOQL uses old name
4. `docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md:51` — "Before" SOQL uses old name

Both documents already use the new name in other sections (line 29 of research doc, lines 13/31 of solutions doc), so the old references are inconsistencies rather than intentional historical snapshots.

## Proposed Solutions

### Option A: Update all 4 references in this PR
- Replace old name with new name in all 4 locations
- Keeps the rename fully consistent across the entire repo
- **Effort**: Small
- **Risk**: None

### Option B: Leave as historical record
- These are in "before" code examples and research context
- Add a comment noting the rename for clarity
- **Effort**: Small
- **Risk**: Could confuse developers or agents reading these docs

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] No references to `ReplicatedVendorPortalCredential__mdt` remain in the repo (or all are annotated as historical)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of branch fix/claude/adds-vendor-portal-credential-cmt | Docs already mix old and new names internally |

## Resources

- Branch: fix/claude/adds-vendor-portal-credential-cmt
- Commit: 996433b
