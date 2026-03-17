---
title: "FLS Least-Privilege Hardening for Replicated_Instance__c"
category: security-issues
date: 2026-03-17
tags:
  - field-level-security
  - FLS
  - least-privilege
  - Replicated_Instance__c
  - profiles
  - salesforce-dx
  - code-review
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
  - "#20"
  - "#25"
  - "#29"
  - "#30"
  - "#31"
  - "#32"
---

# FLS Least-Privilege Hardening for Replicated_Instance__c

## Problem

After PR #25 added field-level security for `Replicated_Instance__c`, code review by 6 parallel agents identified two issues with the FLS configuration:

1. **Admin editable=true was redundant**: The Admin profile had `editable=true` on all 10 fields, but `ModifyAllData` (line 625 of Admin.profile-meta.xml) overrides all FLS. This made `editable=true` functionally meaningless while contradicting the documented "read-only in SF" intent of the object.

2. **All profiles had readable=true violating least privilege**: Every non-Admin profile could read all 10 fields regardless of role relevance. The existing `Product2` FLS already used `readable=false` for technical fields on non-technical profiles — the `Replicated_Instance__c` configuration was inconsistent with this established pattern.

## Root Cause

The initial FLS configuration prioritized completeness over precision. When field permissions were added to close the gap from PR #15 (issue #7), the approach was "grant read access everywhere, edit only for Admin." This binary model missed the nuance that:

- `ModifyAllData` renders Admin FLS editable settings purely informational
- Different roles have different data needs (Support needs infrastructure details; Marketing needs usage metrics; ContractManager needs minimal context)
- The existing `Product2` FLS already demonstrated role-differentiated `readable` settings

## Solution

### Admin: editable=false (documentation-as-code)

Changed all 10 fields from `editable=true` to `editable=false`. Since `ModifyAllData` overrides FLS entirely, this is a semantic change — the FLS now accurately documents that `Replicated_Instance__c` is read-only, with `ModifyAllData` as the explicit escape hatch for troubleshooting.

### Non-Admin: Role-based readable permissions

Implemented differentiated `readable` settings based on each profile's business function:

| Field | Admin | Sales | Support | Marketing* | ContractMgr |
|-------|-------|-------|---------|-----------|-------------|
| Account__c | r | r | r | r | r |
| Status__c | r | r | r | r | r |
| App_Version__c | r | r | r | - | - |
| Instance_Id__c | r | - | r | - | - |
| Cloud_Provider__c | r | - | r | - | - |
| K8s_Distribution__c | r | - | r | - | - |
| Daily_Active_Users__c | r | r | - | r | - |
| Monthly_Active_Users__c | r | r | - | r | - |
| First_Check_In__c | r | r | r | - | - |
| Last_Check_In__c | r | r | r | - | - |

*Both Custom: Marketing Profile and MarketingProfile use the same permissions.

### Role rationale

- **Admin**: Full read via FLS; full write via `ModifyAllData` (troubleshooting)
- **Support**: All fields readable (troubleshooting requires infrastructure details like K8s distribution, cloud provider, instance ID)
- **Sales**: Customer-facing data — account, status, usage metrics, app version, check-in times (no infrastructure internals)
- **Marketing**: Aggregate metrics only — account, status, DAU, MAU (no technical or temporal fields)
- **ContractManager**: Minimal — account relationship and status only (contractual context)

### Field-by-field rationale

- **Account__c** (universal): Core relationship field; all roles need customer context
- **Status__c** (universal): Operational health indicator relevant to all functions
- **App_Version__c** (Admin, Sales, Support): Version context for customer conversations and diagnostics
- **Instance_Id__c** (Admin, Support): Replicated platform reconciliation key; only needed for technical diagnostics
- **Cloud_Provider__c** (Admin, Support): Infrastructure metadata for troubleshooting
- **K8s_Distribution__c** (Admin, Support): Deployment detail for technical support
- **Daily/Monthly_Active_Users__c** (Admin, Sales, Marketing): Business metrics for engagement tracking and reporting
- **First/Last_Check_In__c** (Admin, Sales, Support): Adoption and liveness signals for customer engagement and diagnostics

## Implementation Details

- All `editable` values set to `false` across all 6 profiles (read-only object)
- `readable` values differentiated per profile based on the matrix above
- XML formatting preserved: 4-space indent, `editable` before `field` before `readable`
- Alphabetical field ordering maintained within each profile
- Documentation in `docs/solutions/security-issues/missing-field-level-security-configuration.md` updated with new permission matrix

## Verification

```bash
# Verify Admin: all editable=false, all readable=true
grep -B1 "Replicated_Instance__c" create-license/main/default/profiles/Admin.profile-meta.xml | grep editable
# Expected: all <editable>false</editable>

# Verify ContractManager: only Account__c and Status__c readable
grep -A1 "Replicated_Instance__c" create-license/main/default/profiles/ContractManager.profile-meta.xml | grep readable
# Expected: 2 true, 8 false

# Verify Support: all readable=true (full troubleshooting access)
grep -A1 "Replicated_Instance__c" "create-license/main/default/profiles/Custom%3A Support Profile.profile-meta.xml" | grep -c "readable>true"
# Expected: 10

# Full matrix validation
for f in create-license/main/default/profiles/*.profile-meta.xml; do
  name=$(basename "$f")
  readable_count=$(grep -A1 "Replicated_Instance__c" "$f" | grep -c "readable>true")
  echo "$name: $readable_count readable fields"
done
# Expected: Admin=10, Sales=7, Support=10, Marketing=4, MarketingProfile=4, ContractManager=2
```

## Prevention

### FLS should reflect business roles, not binary access

When configuring FLS for a new object, don't start with `readable=true` for all profiles. Instead:

1. Start with `readable=false` and `editable=false` as the baseline for all profiles
2. For each profile, ask: "What fields does this role need to do their job?"
3. Grant `readable=true` only where there's a documented business reason
4. Grant `editable=true` only where the profile must write (rare for webhook-populated objects)

### Admin editable should match intent, not function

For profiles with `ModifyAllData`, FLS `editable` is informational. Set it to match the object's intended access pattern:
- Read-only objects (populated by webhooks/triggers): `editable=false`
- User-editable objects: `editable=true`

This makes FLS configurations self-documenting code.

### FLS review checklist (extended)

- [ ] Does each `readable=true` map to a named role's business function?
- [ ] Are infrastructure/technical fields restricted to technical profiles (Admin, Support)?
- [ ] Are business metrics restricted to relevant profiles (Sales, Marketing)?
- [ ] Is Admin `editable` consistent with the object's data flow (read-only vs user-editable)?
- [ ] Does the pattern match existing FLS on similar objects (e.g., Product2)?
- [ ] Are there any profiles with identical permissions that should be differentiated?

## Related Documentation

- [Missing FLS Configuration](./missing-field-level-security-configuration.md) — Original gap closure (no FLS at all)
- [Data Model Hardening Review](../integration-issues/salesforce-data-model-review-hardening.md) — PR #15 review that identified FLS as follow-up
- [Bidirectional Sync Loop Prevention](../integration-issues/bidirectional-sync-loop-prevention.md) — SyncGuard context for why Instance__c is webhook-populated

### Follow-up Issues Filed

| Issue | Description |
|-------|-------------|
| #29 | Missing FLS for Account (4), Lead (2), Product2 (3) custom fields |
| #30 | Add objectPermissions for Replicated_Instance__c (defense-in-depth) |
| #31 | Order.LicenseId__c editable=true on non-Admin profiles (pre-existing) |
| #32 | Verify FLS deployment to Salesforce org |
