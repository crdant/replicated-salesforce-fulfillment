---
title: "Incorrect Field-Level Security Pattern on Product2 Custom Fields"
category: "security-issues"
severity: "medium"
date: "2026-03-18"
tags:
  - fls
  - field-level-security
  - salesforce
  - profiles
  - product2
  - pattern-consistency
  - access-control
affects:
  - "Admin.profile-meta.xml"
  - "Custom: Support Profile.profile-meta.xml"
  - "Product2.IsSnapshotSupported__c"
  - "Product2.IsSupportBundleUploadEnabled__c"
problem_type: "security_issue"
context:
  branch: "fix/claude/adds-missing-product2-fields"
  commit: "ed0ebee"
  fix_commit: "6ad3bf6"
---

# Incorrect Field-Level Security Pattern on Product2 Custom Fields

## Problem

When adding FLS (field-level security) for two new Product2 custom fields (`IsSnapshotSupported__c` and `IsSupportBundleUploadEnabled__c`), the wrong FLS convention was used as a template. The implementation followed the `Replicated_Instance__c` convention (read-only sync data) instead of the existing `Product2.Is*__c` convention (admin-editable entitlements).

This resulted in two profile-level misconfigurations:

1. **Admin profile**: New fields had `editable=false` while all 4 existing sibling `Is*__c` fields had `editable=true`. Admins could not configure these entitlements through the UI.
2. **Support profile**: New fields had `readable=true` while all 4 existing sibling `Is*__c` fields had `readable=false`. Support users could see entitlement flags they had no business need for.

The other 4 profiles (ContractManager, Marketing, Sales, MarketingProfile) were correct — all had `editable=false, readable=false` matching the existing pattern.

## Root Cause

The commit message confirmed the source of the error: it followed "the existing Replicated_Instance__c convention (read-only for Admin and Support, no access for others)." This was the wrong convention to follow. The two FLS conventions in this codebase serve fundamentally different purposes:

- **`Replicated_Instance__c` fields**: System-populated via inbound webhook sync. Read-only everywhere because humans should never edit sync data.
- **`Product2.Is*__c` fields**: Human-authored entitlement configuration. Editable by Admin because admins configure product entitlements that flow to the Replicated API.

The new fields are Product2 entitlement checkboxes identical in structure to their siblings (`IsAdminConsoleEnabled__c`, `IsAirgapEnabled__c`, `IsEmbeddedClusterEnabled__c`, `IsAddOn__c`). There is no structural or semantic reason for different FLS.

## Solution

### Fix 1: Admin profile — restore editable access

In `create-license/main/default/profiles/Admin.profile-meta.xml`, change `editable=false` to `editable=true` for both fields:

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

### Fix 2: Support profile — remove unnecessary read access

In `create-license/main/default/profiles/Custom%3A Support Profile.profile-meta.xml`, change `readable=true` to `readable=false` for both fields:

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

### Verification

1. Confirm all `Product2.Is*__c` fields in the Admin profile have `editable=true, readable=true`
2. Confirm all `Product2.Is*__c` fields in the Support profile have `editable=false, readable=false`
3. Confirm the 4 other profiles are unchanged (all `editable=false, readable=false`)
4. Deploy with `make deploy` and verify Admin can toggle both fields on a Product2 record

## Detection

All 4 code review agents independently identified both issues:

- **security-sentinel**: Flagged as medium-severity access control mismatch
- **architecture-strategist**: Identified wrong convention used as template
- **pattern-recognition-specialist**: Detected the pattern break by comparing sibling field FLS
- **code-simplicity-reviewer**: Flagged the inconsistency as an unnecessary special case

The consistent detection across agents validates that comparing new field FLS against existing sibling fields is an effective review strategy.

## Prevention

### Checklist for Adding New FLS Entries

- [ ] Identify the parent object (`Product2`, `Replicated_Instance__c`, etc.)
- [ ] Open the target profile XML and examine 2-3 existing fields on the **same object**
- [ ] Copy the FLS structure from those sibling fields, changing only the field name
- [ ] If your FLS differs from siblings, document why in the commit message
- [ ] Verify the pattern across all 6 profiles, not just one
- [ ] Run a diff review comparing new FLS blocks against existing ones

### FLS Convention Quick Reference

| Aspect | `Replicated_Instance__c` Fields | `Product2.Is*__c` Entitlement Fields |
|--------|--------------------------------|--------------------------------------|
| **Data origin** | System-populated via webhook sync | Human-authored in Salesforce |
| **Admin** | readable=true, editable=false | readable=true, editable=true |
| **Support** | readable=true, editable=false | readable=false, editable=false |
| **Sales/Marketing/Contract** | readable=varies, editable=false | readable=false, editable=false |
| **Use case** | Instance telemetry, sync status | App/channel/entitlement configuration |

### Key Principle

**Always model new FLS after sibling fields on the same object, not fields from other objects.** The parent object determines the convention because it reflects the field's data origin and intended access model.

## Related Documentation

- [Missing Field-Level Security Configuration](missing-field-level-security-configuration.md) — Original FLS gap discovery and fix for `Replicated_Instance__c`
- [FLS Least-Privilege Hardening](fls-least-privilege-hardening-replicated-instance.md) — Follow-up hardening that established the role-based readable patterns; documents issue #29 for remaining FLS gaps
- [Salesforce Data Model Review and Hardening](../integration-issues/salesforce-data-model-review-hardening.md) — Broader data model review establishing the atomic metadata change principle
- Todo 003: Missing FLS for Account (4 fields), Lead (2 fields), and Product2.Application__c — partially addressed by this branch
- GitHub issues: #20 (original FLS requirement), #25 (Replicated_Instance__c FLS PR), #29 (remaining FLS gaps)
