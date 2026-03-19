---
title: "Salesforce Deployment Failure: Explicit FLS on Required Field"
category: build-errors
date: 2026-03-18
tags:
  - salesforce
  - field-level-security
  - FLS
  - deployment
  - metadata
  - profiles
  - required-field
  - Replicated_Instance__c
severity: high
components:
  - "create-license/main/default/profiles/Admin.profile-meta.xml"
  - "create-license/main/default/profiles/ContractManager.profile-meta.xml"
  - "create-license/main/default/profiles/Custom: Marketing Profile.profile-meta.xml"
  - "create-license/main/default/profiles/Custom: Sales Profile.profile-meta.xml"
  - "create-license/main/default/profiles/Custom: Support Profile.profile-meta.xml"
  - "create-license/main/default/profiles/MarketingProfile.profile-meta.xml"
  - "create-license/main/default/objects/Replicated_Instance__c/fields/Instance_Id__c.field-meta.xml"
related_issues:
  - "#20"
  - "#25"
  - "#32"
---

# Salesforce Deployment Failure: Explicit FLS on Required Field

## Problem

Salesforce deployment failed because explicit `<fieldPermissions>` entries existed in profile XML files for `Replicated_Instance__c.Instance_Id__c` — a field defined with `<required>true</required>`. The Salesforce Metadata API rejects deployments that include explicit field-level security (FLS) for required non-Lookup fields.

## Root Cause

PR #25 (commit `919a948`, "Add field-level security for Replicated_Instance__c fields") added `<fieldPermissions>` blocks for all 10 custom fields on `Replicated_Instance__c` across 6 profiles. The implementation iterated over all fields without checking whether each field was eligible for explicit FLS. `Instance_Id__c` has `<required>true</required>`, making it ineligible — Salesforce rejects explicit FLS for all required fields regardless of type.

The field definition:

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Instance_Id__c</fullName>
    <description>Replicated instance ID — reconciliation key</description>
    <externalId>true</externalId>
    <label>Instance Id</label>
    <length>255</length>
    <required>true</required>
    <type>Text</type>
    <unique>true</unique>
</CustomField>
```

## Salesforce Platform Behavior

Required fields in Salesforce (those with `<required>true</required>`) follow special rules:

| Field Type | Required? | Explicit FLS Allowed? | Visibility |
|------------|-----------|----------------------|------------|
| Any type (Text, Number, Lookup, etc.) | `true` | No — deployment rejected | Implicit read for all profiles |
| Any type | `false` | Yes | Configurable per profile |
| Formula, Roll-up Summary | any | No | Follows source field visibility |

Required fields get automatic visibility at the platform level regardless of field type. You cannot restrict a required field's visibility through profile-level FLS — Salesforce enforces this during metadata deployment validation. This applies equally to Lookup/relationship fields and non-Lookup fields.

## Solution

Commit `1da4108` removed the 5-line `<fieldPermissions>` block for `Instance_Id__c` from all 6 profiles (30 lines deleted, 0 added).

Each removed block:

```xml
<!-- REMOVED — Salesforce rejects FLS for required non-Lookup fields -->
<fieldPermissions>
    <editable>false</editable>
    <field>Replicated_Instance__c.Instance_Id__c</field>
    <readable>true</readable>  <!-- or false, depending on profile -->
</fieldPermissions>
```

The other 9 fields on `Replicated_Instance__c` retain their explicit FLS entries with role-based least-privilege `readable` settings.

### Security Trade-off

The original FLS matrix intended `Instance_Id__c` to be visible only to Admin and Support profiles. Since it is a required field, all profiles now have implicit read access. This is acceptable because the field contains a Replicated platform identifier (not PII or a secret).

If visibility restriction is critical for a required field, consider enforcing the requirement at the Apex layer (e.g., a before-insert trigger) instead of using the `<required>true</required>` field attribute, which would allow explicit FLS control.

## Verification

```bash
# Confirm Instance_Id__c has no FLS entries in any profile
grep -r "Instance_Id__c" create-license/main/default/profiles/
# Expected: no output

# Confirm other Replicated_Instance__c fields still have FLS (9 per profile)
grep -c "Replicated_Instance__c" create-license/main/default/profiles/*.profile-meta.xml
# Expected: 9 per file, 54 total

# Deploy successfully
make deploy
```

## Prevention

### Check field eligibility before adding FLS

When adding `<fieldPermissions>` to profiles for a new field, first check the field definition:

1. Open the `.field-meta.xml` file
2. If `<required>true</required>` → do NOT add FLS entries (regardless of field type, including Lookups)
3. If `<required>false</required>` → FLS entries are required for all profiles

### PR review checklist

When reviewing a PR that modifies profile metadata:

- [ ] Are new `<fieldPermissions>` entries being added?
- [ ] For each new entry, has the field definition been checked?
- [ ] Are any fields `<required>true</required>`? If so, FLS entries must be removed (all required fields, including Lookups).
- [ ] Field count in `objects/` matches fieldPermissions count per profile (minus required non-Lookup fields)?

### Document the constraint in field metadata

For required fields, state the FLS expectation in the field description:

```xml
<description>
    Replicated instance ID — reconciliation key.
    FLS NOTE: Required non-Lookup field. Salesforce auto-manages visibility.
    Do not add fieldPermissions entries to profiles.
</description>
```

### Pre-deployment validation

```bash
# Find required fields (any type — Salesforce rejects FLS for all required fields)
for f in create-license/main/default/objects/*/fields/*.field-meta.xml; do
  is_required=$(grep -c '<required>true</required>' "$f" 2>/dev/null || echo 0)
  if [ "$is_required" -eq 1 ]; then
    field=$(grep -oP '(?<=<fullName>)[^<]+' "$f")
    object=$(basename "$(dirname "$(dirname "$f")")")
    # Check if any profile has FLS for this field
    if grep -rq "${object}.${field}" create-license/main/default/profiles/; then
      echo "ERROR: ${object}.${field} is required but has FLS entries"
    fi
  fi
done
```

## Related Documentation

- [Missing FLS Configuration](../security-issues/missing-field-level-security-configuration.md) — Original FLS gap closure (PR #25)
- [FLS Least-Privilege Hardening](../security-issues/fls-least-privilege-hardening-replicated-instance.md) — Role-based FLS refinement
- [Data Model Hardening Review](../integration-issues/salesforce-data-model-review-hardening.md) — PR #15 review that defined Instance_Id__c as required

### Issue Dependencies

| Issue | Relationship |
|-------|-------------|
| #20 | Added FLS for Replicated_Instance__c fields (introduced the bug) |
| #25 | PR that merged the FLS additions |
| #32 | Verify FLS deployment to Salesforce org |
