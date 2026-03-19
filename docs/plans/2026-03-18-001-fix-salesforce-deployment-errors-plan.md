---
title: "fix: Resolve Salesforce deployment errors on new org"
type: fix
status: active
date: 2026-03-18
---

# Fix: Resolve Salesforce deployment errors on new org

## Overview

`make deploy` fails with 15 errors across 4 root causes when deploying to the new `orgfarm-ce7df7752f-dev-ed` org. Each fix has a pre-created worktree and branch. They are independent but have a recommended merge order to minimize conflicts.

## Fixes

### Fix 1: Add missing Product2 fields to package.xml

**Worktree:** `.worktrees/missing-product2-fields`
**Branch:** `fix/claude/adds-missing-product2-fields`

**Root cause:** `IsSnapshotSupported__c` and `IsSupportBundleUploadEnabled__c` field definitions exist in source (`create-license/main/default/objects/Product2/fields/`) but are not listed in `package.xml` under `<CustomField>`. Three validation rules and the Product Layout reference them, causing 5 deploy errors.

**Changes:**
- [ ] Add to `package.xml` under `<CustomField>`:
  ```xml
  <members>Product2.IsSnapshotSupported__c</members>
  <members>Product2.IsSupportBundleUploadEnabled__c</members>
  ```
- [ ] Add `<fieldPermissions>` entries for both fields to all 6 profiles in `create-license/main/default/profiles/`:
  - `Admin.profile-meta.xml`
  - `ContractManager.profile-meta.xml`
  - `Custom%3A Marketing Profile.profile-meta.xml`
  - `Custom%3A Sales Profile.profile-meta.xml`
  - `Custom%3A Support Profile.profile-meta.xml`
  - `MarketingProfile.profile-meta.xml`
- [ ] Follow existing FLS convention: start from `readable=false` / `editable=false` baseline, grant `readable=true` only to Admin and Support (matching the `Replicated_Instance__c` pattern from PR #25)

**Resolves deploy errors:**
- `Product2.ValidateIsSnapshotSupported` — no CustomField named `Product2.IsSnapshotSupported__c` found
- `Product2.ValidateIsSupportBundleUploadEnabled` — no CustomField named `Product2.IsSupportBundleUploadEnabled__c` found
- `Product2.ValidateNoEntitlementsForAddOns` — Field `IsSnapshotSupported__c` does not exist
- `Product2-Product Layout` — no CustomField named `Product2.IsSupportBundleUploadEnabled__c` found

---

### Fix 2: Remove required from LongTextArea Platform Event field

**Worktree:** `.worktrees/webhook-payload-required`
**Branch:** `fix/claude/removes-required-from-longtextarea`

**Root cause:** `Replicated_Webhook__e.Payload__c` is a `LongTextArea` with `<required>true</required>`. Salesforce does not allow `required=true` on LongTextArea fields for Platform Events.

**Changes:**
- [ ] In `create-license/main/default/objects/Replicated_Webhook__e/fields/Payload__c.field-meta.xml`, change `<required>true</required>` to `<required>false</required>`

**Note:** The webhook receiver code (issue-10 branch) already validates the JSON body before publishing, so removing `required` does not create a runtime gap. No Apex-side changes needed.

**Resolves deploy error:**
- `Replicated_Webhook__e.Payload__c` — Can not specify 'required' for a CustomField of type LongTextArea

---

### Fix 3: Align Apex classes with actual CMT object name

**Worktree:** `.worktrees/credential-cmt`
**Branch:** `fix/claude/adds-vendor-portal-credential-cmt`

**Root cause:** This is a **name mismatch**, not a missing object. The CMT exists as `Replicated_Vendor_Portal_API_Credential__mdt` (in source and `package.xml`), but Apex classes reference the old name `ReplicatedVendorPortalCredential__mdt`. The object was apparently renamed in source without updating the Apex.

**Changes:**
- [ ] In `create-license/main/default/classes/ReplicatedFulfillment.cls`: change `ReplicatedVendorPortalCredential__mdt` to `Replicated_Vendor_Portal_API_Credential__mdt` (lines 8-10, SOQL query)
- [ ] In `create-license/main/default/classes/ReplicatedPlatform.cls`: change `ReplicatedVendorPortalCredential__mdt` to `Replicated_Vendor_Portal_API_Credential__mdt` (line 5, constructor parameter type)
- [ ] Update `CLAUDE.md` — the Key Salesforce Objects section lists the old name `ReplicatedVendorPortalCredential__mdt`
- [ ] Update `README.md` lines 82 and 129 — also reference the old name

**Note:** `ReplicatedCredentialManager` does not exist in the codebase — no update needed there. The `ApiToken__c` field name on the CMT is correct and does not need changing.

**Resolves deploy errors:**
- `ReplicatedFulfillment` — Invalid type: `ReplicatedVendorPortalCredential__mdt`
- `ReplicatedPlatform` — Invalid type: `ReplicatedVendorPortalCredential__mdt`
- `ReplicatedPlatform` — Variable does not exist: credential (cascading from the type error)
- `FulfillOrder` — Invalid type: `ReplicatedFulfillment` (cascading — trigger can't compile because `ReplicatedFulfillment` didn't compile)

---

### Fix 4: Remove FLS entries for required field

**Worktree:** `.worktrees/instance-required-field`
**Branch:** `fix/claude/fixes-required-field-profile-deploy`

**Root cause:** `Replicated_Instance__c.Instance_Id__c` is `required=true`, so Salesforce auto-manages FLS for it. Deploying explicit `<fieldPermissions>` entries for a required field is rejected.

**Changes:**
- [ ] Remove the `<fieldPermissions>` block for `Replicated_Instance__c.Instance_Id__c` from all 6 profile files:
  ```xml
  <!-- DELETE this block from each profile -->
  <fieldPermissions>
      <editable>false</editable>
      <field>Replicated_Instance__c.Instance_Id__c</field>
      <readable>...</readable>
  </fieldPermissions>
  ```

**Note:** The field remains visible to all users because `required=true` implies universal visibility. No runtime impact.

**Resolves deploy errors:**
- All 6 profile errors: "You cannot deploy to a required field: Replicated_Instance__c.Instance_Id__c"

---

## Merge Order

Recommended order to minimize merge conflicts (Fix 1 and Fix 4 both modify the same 6 profile files):

1. **Fix 4** (profile FLS removal) — smallest, pure deletion
2. **Fix 2** (Platform Event field) — isolated, no profile impact
3. **Fix 3** (CMT name alignment) — Apex + docs, no profile impact
4. **Fix 1** (package.xml + FLS additions) — largest scope, rebase onto clean profiles after Fix 4

## Validation

After all four fixes land on `main`:

1. Run `make deploy` — should complete with zero errors
2. Run `ORG_ALIAS=shortrib make import` — should populate sample data
3. Verify field visibility as a non-Admin user if possible
4. Run `sf apex run test --target-org shortrib --test-level RunLocalTests` if test classes exist

## Out of Scope (tracked separately)

- Missing FLS for `Product2.Application__c`, `Account.*`, and `Lead.*` custom fields (see issues #29)
- Named Credentials migration from CMT for API token storage (issue #28)
- `objectPermissions` for `Replicated_Instance__c` (issue #30)
