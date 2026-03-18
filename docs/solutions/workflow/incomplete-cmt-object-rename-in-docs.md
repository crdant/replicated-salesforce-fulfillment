---
title: Incomplete CMT object rename in documentation
category: workflow
date: 2026-03-18
severity: low
tags:
  - salesforce
  - custom-metadata-type
  - naming-consistency
  - documentation
  - rename
components:
  - Replicated_Vendor_Portal_API_Credential__mdt
  - docs/research/2026-03-16-secret-storage-evaluation.md
  - docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md
related_issues:
  - "#28"
related_prs: []
---

# Incomplete CMT object rename in documentation

## Problem

After renaming the Custom Metadata Type reference from `ReplicatedVendorPortalCredential__mdt` to `Replicated_Vendor_Portal_API_Credential__mdt` in all Apex code and primary docs (commit `996433b`), 4 stale references to the old name remained in research and solutions documentation. These documents already used the new name in other sections, creating internal inconsistencies.

## Root Cause

The initial rename correctly updated all executable code (`.cls` files), `package.xml`, `CLAUDE.md`, and `README.md`, but did not search for references in `docs/research/` and `docs/solutions/` subdirectories. These files contained code snippets and prose referencing the old name that weren't naturally reviewed alongside the code changes.

## Investigation

1. Ran `git diff main...HEAD` to review the 4 files changed in the PR
2. Ran `grep` for old name `ReplicatedVendorPortalCredential__mdt` across the entire repo — found 4 remaining references
3. Confirmed the same docs already used the new name elsewhere (internal inconsistency, not intentional historical record)
4. Verified the actual CMT metadata object exists at the correct path with the new name

## Solution

Updated all 4 references across 2 files:

- `docs/research/2026-03-16-secret-storage-evaluation.md:70` — refactoring instruction
- `docs/research/2026-03-16-secret-storage-evaluation.md:175` — "Before" code snippet constructor parameter
- `docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md:49` — "Before" SOQL variable type
- `docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md:51` — "Before" SOQL FROM clause

Verified with `grep` that no old name references remain outside the completed todo file.

## Prevention

**For any identifier rename in this project, run `git grep` for the old name before committing:**

```bash
git grep "OLD_NAME" -- .
```

This catches references in all file types — Apex, XML, markdown, Makefile, data files. The rename is not complete until this returns zero matches.

**Checklist for renames:**

1. Update Apex source code (`.cls`)
2. Update metadata XML (`.xml`, `package.xml`)
3. Update primary docs (`CLAUDE.md`, `README.md`)
4. Search and update `docs/research/` and `docs/solutions/` — especially code snippets in "Before/After" examples
5. Search and update `Makefile` and scripts (`hack/`)
6. Verify: `git grep -i "OLD_NAME" -- .` returns zero matches

## Related

- [Branch naming convention rework](../workflow/branch-naming-convention-rework.md) — analogous naming consistency lesson where implicit conventions caused 3 PRs to be recreated
- [Wrong identifier type in API call](../integration-issues/wrong-identifier-type-in-api-call.md) — naming inconsistency across layers masked a semantic bug; prevention strategy #3 says "Standardize naming across layers"
- [Secret storage evaluation for CMT credentials](../security-issues/secret-storage-evaluation-for-cmt-credentials.md) — one of the files with stale references; documents the CMT's planned migration to Named Credentials (issue #28)
- [Salesforce data model review and hardening](../integration-issues/salesforce-data-model-review-hardening.md) — already used the correct CMT name; established Protected visibility requirement
