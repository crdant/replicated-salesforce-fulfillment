---
title: "Stale destructive changes and missing Account field cause cascading deploy failures"
category: build-errors
date: 2026-03-19
tags:
  - salesforce
  - deployment
  - destructive-changes
  - custom-field
  - field-level-security
  - lead-conversion
  - account-metadata
components:
  - create-license/main/default/destructiveChangesPost.xml
  - create-license/main/default/objects/Account/fields/Replicated_License_Expiry__c.field-meta.xml
  - create-license/main/default/classes/AssetDownloadedHandler.cls
  - create-license/main/default/classes/AssetDownloadedHandlerTest.cls
  - package.xml
  - create-license/main/default/profiles/Admin.profile-meta.xml
  - create-license/main/default/profiles/ContractManager.profile-meta.xml
  - create-license/main/default/profiles/Custom%3A Marketing Profile.profile-meta.xml
  - create-license/main/default/profiles/Custom%3A Sales Profile.profile-meta.xml
  - create-license/main/default/profiles/Custom%3A Support Profile.profile-meta.xml
  - create-license/main/default/profiles/MarketingProfile.profile-meta.xml
severity: medium
time_to_resolve: 20 minutes
related_pr: 77
related_issues:
  - "#73"
---

# Stale destructive changes and missing Account field cause cascading deploy failures

## Problem

Every `make deploy` produced 6 component failures from two independent root causes, blocking all deployments regardless of what code was being pushed.

**Destructive changes errors (2 failures):**

```
No CustomObject named: Replicated_Vendor_Portal_API_Credential__mdt found
No RemoteSiteSetting named: ReplicatedVendorPortal found
```

**Missing field errors (4 failures, cascading):**

```
Variable does not exist: Replicated_License_Expiry__c (137:21)     — AssetDownloadedHandler.cls
No such column 'Replicated_License_Expiry__c' on entity 'Account'  — AssetDownloadedHandlerTest.cls (×2)
Invalid type: AssetDownloadedHandler (51:27)                        — ReplicatedWebhookSubscriber.trigger
```

The trigger error is a cascade — `AssetDownloadedHandler` fails to compile, so the trigger can't resolve the type.

## Root Cause

### Stale destructive changes

`destructiveChangesPost.xml` listed two metadata items for deletion that had already been removed from the org in a prior deploy cycle. Salesforce treats deletion of non-existent metadata as a hard error, blocking the entire deployment.

### Missing Account custom field

`Replicated_License_Expiry__c` was created on Lead (to capture trial expiry during signup) but never mirrored onto Account. The `AssetDownloadedHandler` carries over license fields from Lead to Account during conversion (line 137), requiring the field to exist on both objects. Three pieces were missing:

1. The field definition XML (`objects/Account/fields/Replicated_License_Expiry__c.field-meta.xml`)
2. The `package.xml` entry under `CustomField`
3. Field-level security entries in all 6 profiles

## Solution

### Stale destructive changes

Emptied the manifest to contain only the version wrapper:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <version>61.0</version>
</Package>
```

### Missing Account field

Created the field definition, matching the Lead equivalent:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Replicated_License_Expiry__c</fullName>
    <description>Replicated license expiration date</description>
    <externalId>false</externalId>
    <label>Replicated License Expiry</label>
    <required>false</required>
    <trackFeedHistory>false</trackFeedHistory>
    <type>Date</type>
</CustomField>
```

Added to `package.xml`:

```xml
<members>Account.Replicated_License_Expiry__c</members>
```

Added `fieldPermissions` to all 6 profiles, following the pattern established by sibling field `Replicated_License_Type__c`:

| Profile | readable |
|---------|----------|
| Admin | true |
| Custom: Support Profile | true |
| Custom: Sales Profile | true |
| Custom: Marketing Profile | false |
| MarketingProfile | false |
| ContractManager | false |

All profiles set `editable=false` (system-managed sync field).

## Prevention

### Destructive changes hygiene

- [ ] Before committing `destructiveChangesPost.xml`, verify every entry still exists in the target org
- [ ] After a successful deploy that includes destructive changes, remove the completed entries from the manifest
- [ ] If the manifest is empty, leave only the version wrapper — do not delete the file (the deploy command references it)

### Custom field creation across related objects

- [ ] When adding a field to Lead that will be referenced during Lead conversion, create it on Account at the same time
- [ ] The field definition, `package.xml` entry, and FLS across all profiles must ship together as an atomic unit
- [ ] Match FLS patterns to sibling fields on the same object — use `Grep` for `Account.Replicated_` to see the established pattern
- [ ] Run `make deploy` after adding the field to catch compile errors before pushing

### Field carry-over checklist for Lead conversion

When `AssetDownloadedHandler` (or any handler) copies fields from Lead to Account, verify all of these exist on Account:

- [ ] `Replicated_Customer_Id__c`
- [ ] `Replicated_License_Type__c`
- [ ] `Replicated_Channel__c`
- [ ] `Replicated_License_Expiry__c`

## Cross-References

- [Webhook event type naming mismatch](../integration-issues/webhook-event-type-naming-mismatch.md) — Fixed in the same PR
- [Trial handler bulkification](../integration-issues/trial-handler-bulkification-governor-limit.md) — Established the Lead conversion field carry-over pattern
- [Missing FLS configuration](../security-issues/missing-field-level-security-configuration.md) — FLS pattern for Replicated sync fields
- [Incorrect FLS pattern for Product2](../security-issues/incorrect-fls-pattern-product2-custom-fields.md) — Sibling field FLS matching convention
- [FLS required field deployment rejection](salesforce-fls-required-field-deployment-rejection.md) — Related deploy failure pattern
- PR #77: Fixes all three issues (event types, destructive changes, missing field)
- PR #50: Introduced `AssetDownloadedHandler` with the field reference
