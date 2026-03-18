---
status: pending
priority: p1
issue_id: "008"
tags:
  - code-review
  - security
  - field-level-security
  - profiles
  - least-privilege
  - pattern-break
dependencies: []
---

# Support profile readable=true on new Product2 Is*__c fields breaks least-privilege pattern

## Problem Statement

The two new Product2 fields (`IsSnapshotSupported__c` and `IsSupportBundleUploadEnabled__c`) are set to `readable=true` on the Custom: Support Profile, while all four existing sibling `Is*__c` entitlement fields use `readable=false`. Support users currently see none of the existing entitlement booleans but would suddenly see these two new ones.

The `readable=true` matches the `Replicated_Instance__c` pattern (which is correct for instance data that support staff need for troubleshooting), but is wrong for Product2 entitlement configuration fields.

## Findings

All 4 review agents independently identified this as a bug:

- **Security Sentinel**: Medium severity. Violates least-privilege by granting unnecessary read access. The word "Support" in `IsSupportBundleUploadEnabled__c` may have led to an assumption that Support users need access, but these are product entitlement configuration fields, not support ticket fields.
- **Architecture Strategist**: The Support Profile gives the new fields `readable=true` while all other `Product2.Is*__c` fields have `readable=false`. Inconsistent information exposure violating least-privilege.
- **Pattern Recognition Specialist**: HIGH severity. Verified all six profiles — the `readable=true` deviation only appears in Custom: Support Profile. The other four non-Admin profiles are consistent (`readable=false`). This isolates it as a bug, not a deliberate policy.
- **Code Simplicity Reviewer**: If support doesn't need to see airgap/embedded-cluster/admin-console flags, they don't need to see snapshot/support-bundle flags either.
- **Learnings Researcher**: Documented convention: "Start with `readable=false` as baseline, then grant access only where there is a documented business reason."

## Proposed Solutions

### Option A: Set readable=false on Support profile for both new fields (Recommended)

In `Custom%3A Support Profile.profile-meta.xml`, change lines 44 and 49 from `<readable>true</readable>` to `<readable>false</readable>`:

```xml
<fieldPermissions>
    <editable>false</editable>
    <field>Product2.IsSnapshotSupported__c</field>
    <readable>false</readable>
</fieldPermissions>
<fieldPermissions>
    <editable>false</editable>
    <field>Product2.IsSupportBundleUploadEnabled__c</field>
    <readable>false</readable>
</fieldPermissions>
```

- **Pros**: Matches all existing Product2 `Is*__c` fields on Support, restores least-privilege, eliminates inconsistency
- **Cons**: None
- **Effort**: Small (2 line changes in 1 file)
- **Risk**: None

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected file**: `create-license/main/default/profiles/Custom%3A Support Profile.profile-meta.xml` (lines 41-50)
- **Root cause**: Same as todo 007 — FLS modeled after `Replicated_Instance__c` (readable for Support) instead of existing `Product2.Is*__c` (no access for Support)
- **Verification**: This deviation is isolated to Support Profile only. ContractManager, Marketing, Sales, and MarketingProfile are all correctly `readable=false`.

## Acceptance Criteria

- [ ] `IsSnapshotSupported__c` has `readable=false` on Custom: Support Profile
- [ ] `IsSupportBundleUploadEnabled__c` has `readable=false` on Custom: Support Profile
- [ ] FLS pattern matches all other `Product2.Is*__c` fields on Support

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of fix/claude/adds-missing-product2-fields | All 4 review agents independently flagged; only Support Profile has this deviation |

## Resources

- Commit: ed0ebee
- Documented convention: `docs/solutions/security-issues/fls-least-privilege-hardening-replicated-instance.md`
- Existing pattern: Support profile lines 21-40 (existing `Is*__c` fields all `readable=false`)
