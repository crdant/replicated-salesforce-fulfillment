---
title: Add Replicated_Download__c Custom Object and Order.FulfilledAt__c Field
category: integration-issues
date: 2026-03-19
tags: [salesforce, custom-object, metadata, salesforce-dx, replicated-platform, field-level-security, schema]
components: [Replicated_Download__c, Order.FulfilledAt__c, create-license/main/default/objects, create-license/main/default/profiles, package.xml]
symptoms: [missing custom object for tracking asset downloads, no FulfilledAt timestamp on Order, deploy failure due to stale destructiveChangesPost.xml]
root_cause: New Salesforce metadata schema required for Replicated asset download tracking — the challenge was correctly replicating all metadata patterns across object definitions, field definitions, profile FLS, objectPermissions, and package.xml
severity: low
resolution_time: quick
---

## Problem

GitHub issue #84 required creating the `Replicated_Download__c` custom object to track asset downloads from the Replicated Platform, along with an `Order.FulfilledAt__c` DateTime field for marking paid order fulfillment. The task involved generating all required Salesforce DX metadata: the object definition (with an AutoNumber nameField using pattern `DL-{0000}`), 9 field definitions, field-level security entries across 6 profiles, objectPermissions entries for 4 custom profiles, and `package.xml` registration. An initial deploy failed due to stale `destructiveChangesPost.xml` entries (pre-existing on main), resolved by rebasing.

## Root Cause

The challenge was understanding the exact XML patterns Salesforce DX requires for each artifact type and how they vary by field type, object type, and profile type. The existing `Replicated_Instance__c` object served as the reference pattern. Key things that needed to be understood:

- Object-meta.xml is minimal: only `deploymentStatus`, `label`, `nameField`, `pluralLabel`, `sharingModel`
- AutoNumber name fields require `displayFormat` and `type=AutoNumber` instead of just `type=Text`
- Required Lookup fields (like `Account__c`) do **not** get `fieldPermissions` entries in profiles
- Standard object fields (`Order.FulfilledAt__c`) need a `trackHistory` element
- `objectPermissions` entries only go in custom profiles (Custom:Sales, Custom:Marketing, Custom:Support, MarketingProfile), **not** Admin or ContractManager
- All `fieldPermissions` and `objectPermissions` entries are alphabetically ordered by object/field name
- Admin profile gets `editable=true` for Order standard object fields; all others get `editable=false`

## Solution

### Step 1: Create the object definition

Create `Replicated_Download__c.object-meta.xml` with AutoNumber naming:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <label>Replicated Download</label>
    <nameField>
        <displayFormat>DL-{0000}</displayFormat>
        <label>Download Number</label>
        <type>AutoNumber</type>
    </nameField>
    <pluralLabel>Replicated Downloads</pluralLabel>
    <sharingModel>Read</sharingModel>
</CustomObject>
```

### Step 2: Create field definitions

Nine fields under `objects/Replicated_Download__c/fields/`:
- `Account__c` (Lookup, required, Restrict delete) — no FLS entry needed
- `App_Name__c` (Text 255), `Asset_Name__c` (Text 255), `Asset_Type__c` (Text 50), `Asset_Version__c` (Text 255), `Channel_Name__c` (Text 255), `License_Type__c` (Text 50), `Replicated_Customer_Id__c` (Text 255) — all need FLS entries
- `Downloaded_At__c` (DateTime) — needs FLS entry

### Step 3: Create the Order field

`Order/fields/FulfilledAt__c.field-meta.xml` — DateTime with `trackHistory=false`, following the `LicenseId__c` pattern.

### Step 4: Update profiles (6 files)

- Add `fieldPermissions` for all 8 non-required `Replicated_Download__c` fields to all 6 profiles (`editable=false`, `readable=true`)
- Add `fieldPermissions` for `Order.FulfilledAt__c` to all 6 profiles (Admin: `editable=true`, others: `editable=false`)
- Add `objectPermissions` for `Replicated_Download__c` to 4 custom profiles only (read/viewAll)
- Insert all entries in alphabetical order

### Step 5: Update package.xml

Add `Replicated_Download__c` to `CustomObject` members and all 9 field entries plus `Order.FulfilledAt__c` to `CustomField` members.

### Step 6: Rebase and deploy

Rebase onto main to pick up the `destructiveChangesPost.xml` fix, then `make deploy` — 85/85 components, 0 errors.

## Key Code Patterns

**Lookup field (required — no FLS entry):**

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Account__c</fullName>
    <description>Parent Account for this Replicated download</description>
    <externalId>false</externalId>
    <label>Account</label>
    <referenceTo>Account</referenceTo>
    <relationshipLabel>Replicated Downloads</relationshipLabel>
    <relationshipName>Replicated_Downloads</relationshipName>
    <deleteConstraint>Restrict</deleteConstraint>
    <required>true</required>
    <type>Lookup</type>
</CustomField>
```

**Text field:**

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Asset_Type__c</fullName>
    <description>Type of downloaded asset</description>
    <externalId>false</externalId>
    <label>Asset Type</label>
    <length>50</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

**DateTime field (custom object — no trackHistory):**

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Downloaded_At__c</fullName>
    <description>Timestamp of the asset download</description>
    <externalId>false</externalId>
    <label>Downloaded At</label>
    <required>false</required>
    <type>DateTime</type>
</CustomField>
```

**DateTime field (standard object — requires trackHistory):**

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>FulfilledAt__c</fullName>
    <description>Timestamp of first paid software download confirming order fulfillment</description>
    <externalId>false</externalId>
    <label>Fulfilled At</label>
    <required>false</required>
    <trackHistory>false</trackHistory>
    <type>DateTime</type>
</CustomField>
```

**objectPermissions (custom profiles only):**

```xml
<objectPermissions>
    <allowCreate>false</allowCreate>
    <allowDelete>false</allowDelete>
    <allowEdit>false</allowEdit>
    <allowRead>true</allowRead>
    <modifyAllRecords>false</modifyAllRecords>
    <object>Replicated_Download__c</object>
    <viewAllRecords>true</viewAllRecords>
</objectPermissions>
```

## Prevention

Checklist for future Salesforce metadata creation:

- [ ] Copy an existing object of the same type as your template before writing XML
- [ ] Verify XML element ordering matches the template exactly
- [ ] Check which profiles include `objectPermissions` for the nearest equivalent existing object and replicate that list exactly
- [ ] Identify required fields before adding FLS entries — required fields do **not** get `fieldPermissions` entries
- [ ] Confirm the correct field-type-specific XML elements (Text: `length`/`unique`; DateTime: neither; Lookup: `referenceTo`/`relationshipLabel`/`relationshipName`/`deleteConstraint`)
- [ ] For fields on standard objects (e.g., Order), include `trackHistory`
- [ ] Sort `fieldPermissions` and `objectPermissions` alphabetically by object name, then field name
- [ ] Run `make deploy` immediately after creating the metadata, not after completing all files
- [ ] Inspect `destructiveChangesPost.xml` before deploying — confirm every referenced object still exists in the org
- [ ] Rebase onto main before beginning metadata work to pick up any destructive change fixes

## Common Pitfalls

- **Adding FLS for required fields**: Salesforce rejects `fieldPermissions` for `required=true` fields. The deploy error is cryptic.
- **Stale destructive changes**: Referencing an already-deleted object in `destructiveChangesPost.xml` fails the entire deploy with "no such object" — unrelated to new metadata.
- **Incomplete profile coverage**: Omitting `objectPermissions` from a profile that should have it means users on that profile silently cannot see the object.
- **Missing Lookup relationship elements**: Omitting any of the four Lookup-specific elements (`referenceTo`, `relationshipLabel`, `relationshipName`, `deleteConstraint`) produces a metadata parse error.
- **Forgetting trackHistory on standard object fields**: Fields on standard objects like Order require `trackHistory` — omitting it produces inconsistent behavior.
- **Wrong alphabetical ordering**: Inserting entries in the wrong position within a profile causes Salesforce to reject the profile metadata.

## Related

- [salesforce-fls-required-field-deployment-rejection](../build-errors/salesforce-fls-required-field-deployment-rejection.md) — required fields cannot have FLS entries
- [incorrect-fls-pattern-product2-custom-fields](../security-issues/incorrect-fls-pattern-product2-custom-fields.md) — FLS should follow sibling fields on the same object
- [missing-field-level-security-configuration](../security-issues/missing-field-level-security-configuration.md) — all optional fields require FLS across all profiles
- [salesforce-data-model-review-hardening](salesforce-data-model-review-hardening.md) — data model patterns and checklist
- GitHub #84 (this issue), #85 (AssetDownloadedHandler depends on this), #86 (EpUserJoinedHandler depends on this)
