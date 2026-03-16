---
title: Salesforce data model review and hardening for Replicated event sync
category: integration-issues
date: 2026-03-16
tags:
  - salesforce
  - data-model
  - code-review
  - external-id
  - platform-events
  - custom-metadata-type
  - security
  - data-integrity
components:
  - Replicated_Instance__c
  - Replicated_Webhook__e
  - Replicated_Webhook_Secret__mdt
  - Account
  - Lead
severity: high
resolution_time: 1 session
pr: 15
issues: [6, 7, 8, 11, 12, 20, 21]
---

# Salesforce Data Model Review and Hardening for Replicated Event Sync

Multi-agent code review of PR #15 identified 11 findings across data integrity, security, and architecture in the Salesforce metadata for Replicated webhook event sync. Eight fixes were applied to prevent runtime failures and improve security posture; two follow-up issues were created for deferred work.

## Problem

PR #15 introduced 24 Salesforce metadata XML files (289 lines) defining the foundation layer for bidirectional sync between Salesforce and the Replicated Platform. The data model included a Platform Event for webhook ingestion, a custom object for instance telemetry, custom fields on Account and Lead, and Custom Metadata Types for credential storage.

Six parallel review agents identified issues in three categories:

**Data Integrity:** External ID fields missing unique constraints (upsert collision risk), Lookup relationships missing delete constraints (orphan risk), picklist with no default, routing field not required.

**Security:** Credential Custom Metadata Types with Public visibility, overly permissive sharing model on read-only data.

**Architecture:** License type and channel fields placed on Lead instead of Account, despite leads always being trials in the self-service flow.

## Root Cause

### Data Integrity

The `Account.Replicated_Customer_Id__c` field was marked as External ID but not unique. The inbound webhook sync uses this field as the upsert key for Account reconciliation. Without uniqueness, duplicate customer IDs across Accounts would cause `System.DmlException` on upsert. Similarly, `Lead.Replicated_Customer_Id__c` wasn't marked as External ID at all, preventing `Database.upsert(leads, Lead.Replicated_Customer_Id__c)` from compiling.

The `Replicated_Instance__c.Account__c` Lookup was `required=true` but had no `deleteConstraint`. Salesforce defaults to SetNull for Lookups, contradicting the required constraint and causing errors or orphaned records on Account deletion.

### Security

Both `Replicated_Vendor_Portal_API_Credential__mdt` and `Replicated_Webhook_Secret__mdt` had `visibility=Public`, making API tokens and HMAC signing secrets queryable via SOQL from any context. `Replicated_Instance__c` used `sharingModel=ReadWrite` despite being read-only data sourced from Replicated.

### Architecture

`Replicated_License_Type__c` and `Replicated_Channel__c` were on Lead, but in the self-service flow leads are always trials. License type is a lifecycle property that changes on the Account (trial to paid to managed). The existing `ReplicatedCustomer` Apex class hardcodes `type = 'prod'`, confirming that license type is an Account-level concern.

## Solution

### Fix 1: Account External ID uniqueness

```xml
<!-- Account/Replicated_Customer_Id__c.field-meta.xml -->
<unique>true</unique>  <!-- was false -->
```

### Fix 2: Lead External ID activation

```xml
<!-- Lead/Replicated_Customer_Id__c.field-meta.xml -->
<externalId>true</externalId>  <!-- was false -->
```

### Fix 3: Instance-to-Account delete constraint

```xml
<!-- Replicated_Instance__c/Account__c.field-meta.xml -->
<deleteConstraint>Restrict</deleteConstraint>  <!-- added -->
```

### Fix 4: Status picklist default

```xml
<!-- Replicated_Instance__c/Status__c.field-meta.xml -->
<value><fullName>Unknown</fullName><default>true</default><label>Unknown</label></value>
```

### Fix 5: Webhook routing field required

```xml
<!-- Replicated_Webhook__e/Customer_Id__c.field-meta.xml -->
<required>true</required>  <!-- was false -->
```

### Fix 6: Instance sharing model

```xml
<!-- Replicated_Instance__c.object-meta.xml -->
<sharingModel>Read</sharingModel>  <!-- was ReadWrite -->
```

### Fix 7 & 8: CMT visibility

```xml
<!-- Both Replicated_Vendor_Portal_API_Credential__mdt and Replicated_Webhook_Secret__mdt -->
<visibility>Protected</visibility>  <!-- was Public -->
```

### Architectural refactoring: fields moved from Lead to Account

- Created `Account/Replicated_License_Type__c.field-meta.xml` and `Account/Replicated_Channel__c.field-meta.xml`
- Deleted the corresponding Lead field files
- Updated `package.xml` to reflect the move
- Noted on issue #8 that `ReplicatedCustomer.cls` should read `type` from Account instead of hardcoding `'prod'`

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Delete constraint | Restrict (not Cascade) | Preserve historical instance data; force explicit cleanup |
| CMT visibility | Protected (not Private) | Allows same-namespace code to query; balances security with access |
| Sharing model | Read (not Controlled) | Simpler than sharing rules; instances are never user-edited |
| Status default | Unknown (not Missing) | Missing implies nonexistence; Unknown indicates pending sync |
| Lead External ID | Yes (not SOQL reconciliation) | Native upsert handles concurrency and race conditions |

## Prevention

### Salesforce Data Model Review Checklist

**External IDs & Upsert Safety:**
- [ ] External ID fields have `<unique>true</unique>` if used for upsert
- [ ] Fields used in `Database.upsert()` calls are marked `<externalId>true</externalId>`
- [ ] Reconciliation keys documented (e.g., "Replicated customer_id = Salesforce Account ID")

**Lookup & Relationship Integrity:**
- [ ] Required Lookups specify `<deleteConstraint>Restrict</deleteConstraint>`
- [ ] Parent-child deletion behavior tested in sandbox

**Picklist Fields:**
- [ ] All picklists have a default value
- [ ] Restricted picklists include a catch-all for unrecognized values

**Platform Events:**
- [ ] Fields used for routing/filtering are `required=true`
- [ ] Platform Events are immutable once published; validate before publish

**Security:**
- [ ] Credential CMTs use `<visibility>Protected</visibility>`
- [ ] Read-only data uses `<sharingModel>Read</sharingModel>`, not ReadWrite
- [ ] Sensitive fields not exposed via Public visibility

**Field Placement:**
- [ ] Lifecycle properties (license type, channel) live on Account, not Lead
- [ ] Fields placed on the entity they describe, not downstream objects

### Anti-Patterns Identified

| Anti-Pattern | Symptom | Fix |
|---|---|---|
| External ID without unique | Upsert DmlException on duplicates | Always pair `externalId=true` with `unique=true` |
| Required Lookup without deleteConstraint | Orphans or errors on parent deletion | Add `deleteConstraint=Restrict` |
| Optional routing field on Platform Event | Silent event drops or null-pointer in subscriber | Make routing fields required |
| Public visibility on credential CMTs | Secrets queryable via SOQL | Use Protected visibility |
| Lifecycle fields on Lead | Data lost or misplaced after conversion | Place on Account (persistent entity) |

## Related

- [PR #15](https://github.com/crdant/replicated-salesforce-fulfillment/pull/15) — Define Salesforce data model for Replicated event sync
- [#6](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6) — Event-driven bidirectional sync (parent epic)
- [#7](https://github.com/crdant/replicated-salesforce-fulfillment/issues/7) — Define Salesforce data model (this issue)
- [#8](https://github.com/crdant/replicated-salesforce-fulfillment/issues/8) — Enterprise Portal invite + fulfillment refactor (ReplicatedCustomer refactoring noted)
- [#11](https://github.com/crdant/replicated-salesforce-fulfillment/issues/11) — Trial lifecycle handlers (depends on these fixes)
- [#12](https://github.com/crdant/replicated-salesforce-fulfillment/issues/12) — Instance and license event handlers
- [#20](https://github.com/crdant/replicated-salesforce-fulfillment/issues/20) — Add field-level security for Instance fields (follow-up)
- [#21](https://github.com/crdant/replicated-salesforce-fulfillment/issues/21) — Evaluate secure secret storage for CMT credentials (follow-up)
