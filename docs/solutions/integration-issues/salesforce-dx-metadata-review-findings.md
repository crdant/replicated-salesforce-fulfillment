---
title: Replicated_Download__c schema design gaps found in code review
category: integration-issues
date: 2026-03-19
tags: [salesforce-dx, custom-object, schema-design, code-review, metadata, field-level-security, external-id, required-fields]
components: [Replicated_Download__c, Order.FulfilledAt__c, CLAUDE.md, create-license/main/default/profiles]
symptoms: [Replicated_Customer_Id__c not indexed for SOQL lookups despite being a reconciliation key, CLAUDE.md missing documentation of new custom object, Downloaded_At__c semantically mandatory timestamp declared as optional field]
root_cause: New custom object metadata authored without applying existing project conventions for external ID indexing, required field declarations, and documentation of key Salesforce objects
severity: medium
resolution_time: quick
---

## Problem

Code review of PR #88 (`Replicated_Download__c` object and `Order.FulfilledAt__c` field) revealed three schema design gaps in the Salesforce DX metadata. All were caught pre-merge by multi-agent review (security-sentinel, architecture-strategist, code-simplicity-reviewer, agent-native-reviewer, learnings-researcher).

1. `Replicated_Customer_Id__c` had `externalId=false` despite the project convention of `externalId=true` on all reconciliation key fields
2. `Downloaded_At__c` was declared optional despite the webhook payload always providing a timestamp
3. `CLAUDE.md` Key Salesforce Objects section did not document the new object

## Root Cause

The developer replicated field content (name, type, length) from existing patterns but missed three convention-level properties that vary by context:

- **`externalId` semantics differ per object**: On `Account`, it enforces uniqueness. On `Replicated_Download__c`, it serves purely as a query index (one customer has many downloads). The developer set `unique=false` correctly but didn't consider that `externalId=true` is still needed for indexing.
- **Default optionality applied uniformly**: All fields were created as `required=false` without evaluating which are guaranteed from the webhook payload.
- **CLAUDE.md updates aren't in the creation checklist**: Documentation was not part of the object creation workflow.

## Solution

### Step 1: Set externalId=true on Replicated_Customer_Id__c

In `create-license/main/default/objects/Replicated_Download__c/fields/Replicated_Customer_Id__c.field-meta.xml`:

**Before:**
```xml
<externalId>false</externalId>
```

**After:**
```xml
<externalId>true</externalId>
```

`unique=false` remains correct — one customer can have many downloads. The `externalId` flag creates a Salesforce-managed index for `WHERE Replicated_Customer_Id__c = :id` queries.

### Step 2: Make Downloaded_At__c required and remove FLS entries

In `create-license/main/default/objects/Replicated_Download__c/fields/Downloaded_At__c.field-meta.xml`:

**Before:**
```xml
<required>false</required>
```

**After:**
```xml
<required>true</required>
```

Because Salesforce rejects `fieldPermissions` entries for required fields (see [salesforce-fls-required-field-deployment-rejection](../build-errors/salesforce-fls-required-field-deployment-rejection.md)), remove the `Downloaded_At__c` FLS block from all 6 profiles:

```xml
<!-- REMOVE this block from each profile -->
<fieldPermissions>
    <editable>false</editable>
    <field>Replicated_Download__c.Downloaded_At__c</field>
    <readable>true</readable>
</fieldPermissions>
```

Profiles affected: Admin, ContractManager, Custom: Marketing Profile, Custom: Sales Profile, Custom: Support Profile, MarketingProfile.

### Step 3: Add new objects to CLAUDE.md

Add two entries to the Key Salesforce Objects section:

```markdown
- `Order.FulfilledAt__c` — Timestamp of first paid software download confirming order fulfillment
- `Replicated_Download__c` — Tracks asset downloads from the Replicated Platform (read-only in SF, linked to Account via Account__c)
```

## Key Code Patterns

**externalId on non-unique reconciliation fields:**

```xml
<!-- Correct: indexed for queries, not enforcing uniqueness -->
<externalId>true</externalId>
<unique>false</unique>
```

Compare with Account where both are true:
```xml
<!-- Account: indexed AND unique (one customer per account) -->
<externalId>true</externalId>
<unique>true</unique>
```

**Required field = no FLS entries:**

When `<required>true</required>`, do not add `fieldPermissions` in any profile. The field is inherently visible. Deploying with FLS on a required field produces a cryptic rejection.

## Prevention

Additions to the Salesforce metadata creation checklist:

- [ ] For every field storing a cross-system identifier, set `externalId=true` — grep existing objects for the same field name to confirm consistent indexing
- [ ] For each field, determine whether the data source guarantees the value — set `required=true` when the upstream webhook/API always provides it
- [ ] If a new custom object was created, add it to CLAUDE.md Key Salesforce Objects with a one-line description including data flow direction (read-only, write, bidirectional)
- [ ] When making a field required, remove its `fieldPermissions` block from all profiles before deploying

**CI automation opportunities:**
- Scan new `.field-meta.xml` files for known reconciliation field patterns and assert `externalId=true`
- Detect new `objects/` directories in PR diff and fail if `CLAUDE.md` is not also modified

## Common Pitfalls

- **Copying field content without copying index flags**: `externalId` is easy to miss because it doesn't affect deployment — only query performance at scale.
- **Uniform optionality**: Defaulting all fields to `required=false` is safe for deployment but loses data integrity guarantees the upstream system provides.
- **Documentation as afterthought**: CLAUDE.md updates are invisible to Salesforce tooling — they only surface during agent-native or documentation reviews.

## Related

- [salesforce-dx-custom-metadata-patterns](salesforce-dx-custom-metadata-patterns.md) — companion doc covering the initial object creation patterns for the same PR
- [salesforce-fls-required-field-deployment-rejection](../build-errors/salesforce-fls-required-field-deployment-rejection.md) — required fields cannot have FLS entries
- [salesforce-data-model-review-hardening](salesforce-data-model-review-hardening.md) — data model review checklist including externalId conventions
- [missing-field-level-security-configuration](../security-issues/missing-field-level-security-configuration.md) — FLS must ship atomically with field definitions
- [code-review-documentation-contract-violations](../build-errors/code-review-documentation-contract-violations.md) — CLAUDE.md must be updated when adding new objects/targets
- GitHub #84 (schema spec), #85 (AssetDownloadedHandler depends on this), #88 (PR reviewed), #90 (deferred Order relationship)
