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

Salesforce deployment fails with "You cannot deploy to a required field" when profile XML files contain explicit `<fieldPermissions>` entries for fields defined with `<required>true</required>`. The Salesforce Metadata API rejects these entries for **all required fields regardless of type** — Text, Lookup, Picklist, Number, and every other field type.

This error has occurred three times in this project:

| Field | Type | PR | Fix |
|-------|------|-----|-----|
| `Replicated_Instance__c.Instance_Id__c` | Text | #25 | Commit `1da4108` |
| `Replicated_Instance__c.Account__c` | Lookup | #37 | PR #37 |
| `Product2.Application__c` | Picklist | #52 | PR #52 |

## Root Cause

PR #25 (commit `919a948`, "Add field-level security for Replicated_Instance__c fields") added `<fieldPermissions>` blocks for all 10 custom fields on `Replicated_Instance__c` across 6 profiles. The implementation iterated over all fields without checking whether each field was eligible for explicit FLS. `Instance_Id__c` (`<required>true</required>`, Text) was caught first. `Account__c` (`<required>true</required>`, Lookup) was missed initially because documentation incorrectly speculated that required Lookups might be exempt. `Application__c` (`<required>true</required>`, Picklist) on Product2 was caught during the PR #52 deployment.

Example field definition that triggers the error:

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

### Misconception: Lookup Exception

Early documentation for this project speculated that required Lookup fields might be exempt from this rule because they serve a relational purpose. **This is wrong.** Deployment failures on `Account__c` (Lookup, PR #37) and `Application__c` (Picklist, PR #52) confirmed there are no field-type exceptions. The Metadata API applies the same rejection to every required field.

## Solution

Remove the entire `<fieldPermissions>` block for any required field from all profile XML files.

Each removed block looks like:

```xml
<!-- REMOVED — Salesforce rejects FLS for all required fields -->
<fieldPermissions>
    <editable>false</editable>
    <field>Replicated_Instance__c.Account__c</field>
    <readable>true</readable>
</fieldPermissions>
```

### Timeline of Fixes

- Commit `1da4108` removed `Instance_Id__c` FLS from 6 profiles (30 lines deleted)
- PR #37 removed `Account__c` FLS from 6 profiles (30 lines deleted)
- PR #52 removed `Application__c` FLS from 6 profiles (30 lines deleted)

### Security Trade-off

Required fields grant implicit read access to all profiles. If visibility restriction is critical, enforce the requirement at the Apex layer (e.g., a before-insert trigger) instead of using the `<required>true</required>` field attribute, which would allow explicit FLS control.

## Verification

```bash
# List all required fields and confirm none have FLS entries in any profile
for f in create-license/main/default/objects/*/fields/*.field-meta.xml; do
  if grep -q '<required>true</required>' "$f" 2>/dev/null; then
    field=$(grep -oP '(?<=<fullName>)[^<]+' "$f")
    object=$(basename "$(dirname "$(dirname "$f")")")
    if grep -rq "${object}.${field}" create-license/main/default/profiles/; then
      echo "FAIL: ${object}.${field} is required but has FLS entries"
    else
      echo "OK:   ${object}.${field} (required, no FLS)"
    fi
  fi
done

# Deploy successfully
make deploy
```

## Prevention

### Check field eligibility before adding FLS

When adding `<fieldPermissions>` to profiles for a new field, first check the field definition:

1. Open the `.field-meta.xml` file
2. If `<required>true</required>` → do NOT add FLS entries (regardless of field type)
3. If `<required>false</required>` or no `<required>` element → FLS entries are required for all profiles

### PR review checklist

When reviewing a PR that modifies profile metadata:

- [ ] Are new `<fieldPermissions>` entries being added?
- [ ] For each new entry, has the field definition been checked?
- [ ] Are any fields `<required>true</required>`? If so, FLS entries must be removed (all required fields, including Lookups).
- [ ] Field count in `objects/` matches fieldPermissions count per profile (minus required fields)?

### Verify claims about field-type exceptions

If documentation or a team member claims a specific field type is exempt from the required-field FLS rule, verify with an actual deployment before relying on the claim. The `Account__c` Lookup case proves that untested assumptions about type-based exceptions propagate and cause repeated failures.

### Pre-deployment validation

```bash
# Find ALL required fields and check for FLS violations
for f in create-license/main/default/objects/*/fields/*.field-meta.xml; do
  if grep -q '<required>true</required>' "$f" 2>/dev/null; then
    field=$(grep -oP '(?<=<fullName>)[^<]+' "$f")
    object=$(basename "$(dirname "$(dirname "$f")")")
    if grep -rq "${object}.${field}" create-license/main/default/profiles/; then
      echo "ERROR: ${object}.${field} is required but has FLS entries"
    fi
  fi
done
```

## Related Documentation

- [Missing FLS Configuration](../security-issues/missing-field-level-security-configuration.md) — Original FLS gap closure (PR #25)
- [FLS Least-Privilege Hardening](../security-issues/fls-least-privilege-hardening-replicated-instance.md) — Role-based FLS refinement
- [Incorrect FLS Pattern on Product2](../security-issues/incorrect-fls-pattern-product2-custom-fields.md) — FLS template mismatch for Product2 fields
- [Data Model Hardening Review](../integration-issues/salesforce-data-model-review-hardening.md) — PR #15 review that defined Instance_Id__c as required

### Issue Dependencies

| Issue | Relationship |
|-------|-------------|
| #20 | Added FLS for Replicated_Instance__c fields (introduced the bug) |
| #25 | PR that merged the FLS additions |
| #32 | Verify FLS deployment to Salesforce org |
| #37 | Removed Account__c FLS (required Lookup) |
| #52 | Removed Application__c FLS (required Picklist), corrected this doc |
