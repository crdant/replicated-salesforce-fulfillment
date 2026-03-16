---
title: "Missing field-level security for Replicated_Instance__c fields"
category: security-issues
date: 2026-03-16
tags:
  - field-level-security
  - FLS
  - Replicated_Instance__c
  - profiles
  - salesforce-dx
severity: medium
components:
  - Replicated_Instance__c
  - Admin.profile-meta.xml
  - ContractManager.profile-meta.xml
  - "Custom: Marketing Profile.profile-meta.xml"
  - "Custom: Sales Profile.profile-meta.xml"
  - "Custom: Support Profile.profile-meta.xml"
  - MarketingProfile.profile-meta.xml
related_issues:
  - "#6"
  - "#7"
  - "#12"
  - "#15"
  - "#20"
---

# Missing Field-Level Security for Replicated_Instance__c Fields

## Problem

The `Replicated_Instance__c` custom object had 10 fields defined in profile metadata but no `<fieldPermissions>` entries in any of the 6 Salesforce profiles. Without explicit FLS, field access was undefined — creating a security gap where sensitive instance data (account relationships, usage metrics, check-in times) had no enforced access control.

## Root Cause

When the data model was defined in PR #15 (issue #7), FLS was intentionally deferred to keep the PR focused on object/field definitions. The field metadata was created in `create-license/main/default/objects/Replicated_Instance__c/fields/` but no corresponding `<fieldPermissions>` entries were added to any profile. The gap existed from commit `08eae60` until commit `8f4fb08`.

## Solution

Added `<fieldPermissions>` XML blocks for all 10 fields across all 6 profiles in `create-license/main/default/profiles/`.

### Admin Profile (read + edit for troubleshooting)

```xml
<fieldPermissions>
    <editable>true</editable>
    <field>Replicated_Instance__c.Account__c</field>
    <readable>true</readable>
</fieldPermissions>
```

### Non-Admin Profiles (read-only)

```xml
<fieldPermissions>
    <editable>false</editable>
    <field>Replicated_Instance__c.Account__c</field>
    <readable>true</readable>
</fieldPermissions>
```

### Fields Secured

All 10 custom fields on `Replicated_Instance__c`:

| Field | Type | Purpose |
|-------|------|---------|
| `Account__c` | Lookup | Owner account relationship |
| `App_Version__c` | Text | Running application version |
| `Cloud_Provider__c` | Text | Infrastructure provider |
| `Daily_Active_Users__c` | Number | Daily usage metric |
| `First_Check_In__c` | DateTime | Initial instance check-in |
| `Instance_Id__c` | Text (External ID) | Replicated instance identifier |
| `K8s_Distribution__c` | Text | Kubernetes distribution |
| `Last_Check_In__c` | DateTime | Most recent check-in |
| `Monthly_Active_Users__c` | Number | Monthly usage metric |
| `Status__c` | Picklist | Instance lifecycle status |

### Profiles Updated

| Profile | editable | readable |
|---------|----------|----------|
| Admin | true | true |
| ContractManager | false | true |
| Custom: Marketing Profile | false | true |
| Custom: Sales Profile | false | true |
| Custom: Support Profile | false | true |
| MarketingProfile | false | true |

### Implementation Details

- Entries inserted alphabetically after existing `Product2` field permissions, before `<layoutAssignments>`
- Each profile received exactly 10 field permission blocks (60 total across 6 profiles)
- Matches existing XML formatting conventions (4-space indent, `editable` before `field` before `readable`)

## Verification

1. **Field count**: `grep -c "Replicated_Instance__c" create-license/main/default/profiles/*.profile-meta.xml` — expect 10 per file, 60 total
2. **Admin editable**: `grep -B1 "Replicated_Instance__c" create-license/main/default/profiles/Admin.profile-meta.xml | grep editable` — all `true`
3. **Non-Admin read-only**: Same grep on other profiles — all `false`
4. **Deploy**: `make deploy` — no validation errors

## Prevention

### Always include FLS with field definitions

When adding custom fields to a Salesforce DX project, the fieldPermissions entries in profiles must ship in the **same PR** as the field definitions. Never defer FLS to a follow-up.

**Atomic PR structure:**
```
objects/Replicated_Instance__c/fields/Status__c.field-meta.xml   <- NEW field
profiles/Admin.profile-meta.xml                                   <- UPDATED with fieldPermissions
profiles/ContractManager.profile-meta.xml                         <- UPDATED with fieldPermissions
...all other profiles                                             <- UPDATED with fieldPermissions
```

### PR review checklist for Salesforce metadata

- [ ] Does the PR add new fields to `objects/*/fields/`?
- [ ] If yes, do ALL profiles have corresponding `<fieldPermissions>` entries?
- [ ] Field count in `objects/` matches fieldPermissions count per profile?
- [ ] Editable/readable settings match the field's intended access pattern?

### Quick validation command

```bash
# Count fields vs fieldPermissions — numbers should match
find create-license/main/default/objects -name "*.field-meta.xml" | wc -l
grep -c "fieldPermissions" create-license/main/default/profiles/Admin.profile-meta.xml
```

## Related Documentation

- [Data model hardening review](../integration-issues/salesforce-data-model-review-hardening.md) — PR #15 review that identified FLS as follow-up
- [Bidirectional sync loop prevention](../integration-issues/bidirectional-sync-loop-prevention.md) — SyncGuard context for webhook-populated fields
- [Event-driven bidirectional sync research](../../research/2026-03-16-event-driven-bidirectional-sync.md) — Architecture context

### Issue Dependencies

| Issue | Relationship |
|-------|-------------|
| #6 | Parent epic (event-driven bidirectional sync) |
| #7 | Defined the data model requirement including FLS |
| #15 | PR that merged the data model without FLS |
| #20 | This issue — added the missing FLS |
| #12 | Instance event handlers — blocked by #20 |
