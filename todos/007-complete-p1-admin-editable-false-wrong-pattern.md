---
status: complete
priority: p1
issue_id: "007"
tags:
  - code-review
  - security
  - field-level-security
  - profiles
  - pattern-break
dependencies: []
---

# Admin profile editable=false on new Product2 Is*__c fields uses wrong convention

## Problem Statement

The two new Product2 fields (`IsSnapshotSupported__c` and `IsSupportBundleUploadEnabled__c`) are set to `editable=false` on the Admin profile, while all four existing sibling `Is*__c` entitlement fields use `editable=true`. The commit message confirms the root cause: it followed "the existing Replicated_Instance__c convention (read-only for Admin)" — but that's the wrong convention. `Replicated_Instance__c` fields are read-only because they're populated by inbound webhook sync. Product2 entitlement fields are the opposite: they're authored by admins in Salesforce and pushed to the Replicated API.

With `editable=false`, an admin cannot toggle snapshot or support bundle upload flags on Product2 records through the UI.

## Findings

All 4 review agents independently identified this as a bug:

- **Security Sentinel**: Medium severity. Incorrect access control model prevents admin configuration. `ModifyAllData` technically overrides, but the semantic intent is wrong.
- **Architecture Strategist**: High priority. The `Replicated_Instance__c` pattern was applied by analogy but is the wrong model for Product2 entitlement configuration fields.
- **Pattern Recognition Specialist**: HIGH severity. The four existing `Is*__c` fields are all `editable=true`; the two new ones are `editable=false`. No structural reason (formula, external ID) justifies the difference.
- **Code Simplicity Reviewer**: Eliminates a special case. One rule (all Product2 boolean entitlement fields are admin-editable) is simpler than two rules with no documented rationale.
- **Learnings Researcher**: Documented institutional knowledge in `docs/solutions/security-issues/fls-least-privilege-hardening-replicated-instance.md` explicitly states: "Admin `editable` should match intent — for objects where users edit data, use `editable=true`."

## Proposed Solutions

### Option A: Set editable=true on Admin profile for both new fields (Recommended)

In `Admin.profile-meta.xml`, change lines 42 and 47 from `<editable>false</editable>` to `<editable>true</editable>`:

```xml
<fieldPermissions>
    <editable>true</editable>
    <field>Product2.IsSnapshotSupported__c</field>
    <readable>true</readable>
</fieldPermissions>
<fieldPermissions>
    <editable>true</editable>
    <field>Product2.IsSupportBundleUploadEnabled__c</field>
    <readable>true</readable>
</fieldPermissions>
```

- **Pros**: Matches all existing Product2 `Is*__c` fields, enables admin configuration, follows documented conventions
- **Cons**: None
- **Effort**: Small (2 line changes in 1 file)
- **Risk**: None — restores intended behavior

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected file**: `create-license/main/default/profiles/Admin.profile-meta.xml` (lines 41-50)
- **Root cause**: Commit modeled FLS after `Replicated_Instance__c` (read-only sync data) instead of existing `Product2.Is*__c` (admin-editable entitlements)

## Acceptance Criteria

- [ ] `IsSnapshotSupported__c` has `editable=true` on Admin profile
- [ ] `IsSupportBundleUploadEnabled__c` has `editable=true` on Admin profile
- [ ] FLS pattern matches all other `Product2.Is*__c` fields on Admin

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of fix/claude/adds-missing-product2-fields | All 4 review agents independently flagged this; wrong convention used as template |

## Resources

- Commit: ed0ebee
- Documented convention: `docs/solutions/security-issues/fls-least-privilege-hardening-replicated-instance.md`
- Existing pattern: Admin profile lines 22-40 (existing `Is*__c` fields all `editable=true`)
