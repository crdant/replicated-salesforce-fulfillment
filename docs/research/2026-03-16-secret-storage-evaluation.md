---
date: 2026-03-16
researcher: Claude
branch: docs/claude/evaluates-secret-storage
repository: crdant/cold-leads-to-hot-signal
topic: "Evaluate secure secret storage for Custom Metadata Type credentials"
tags: [research, salesforce, security, named-credentials, custom-metadata-type, secrets-management]
status: complete
last_updated: 2026-03-16
last_updated_by: Claude
last_updated_note: "Evaluation complete — Named Credentials recommended for API token, Protected CMT acceptable for HMAC secret"
---

# Evaluation: Secure Secret Storage for Custom Metadata Type Credentials

**Date**: 2026-03-16
**Researcher**: Claude
**Branch**: docs/claude/evaluates-secret-storage
**Repository**: crdant/cold-leads-to-hot-signal

## Research Question

The project stores two sensitive credentials as plaintext Text fields in Protected Custom Metadata Types. What is the most appropriate storage mechanism given the security trade-offs and the Developer Edition org context?

## Current State

| Credential | Object | Field | Type | Visibility | Used By |
|---|---|---|---|---|---|
| Replicated Vendor Portal API token | `Replicated_Vendor_Portal_API_Credential__mdt` | `ApiToken__c` | Text(100) | Protected | `ReplicatedFulfillment` → `ReplicatedPlatform` (Authorization header on all HTTP callouts) |
| Webhook HMAC signing secret | `Replicated_Webhook_Secret__mdt` | `Secret__c` | Text(255) | Protected | Not yet implemented (planned for `ReplicatedWebhookReceiver` HMAC-SHA256 verification) |

Both CMTs were changed from Public to Protected visibility in PR #15. The underlying values remain unencrypted plaintext.

## Options Evaluated

### Option 1: Named Credentials (External Credential + Named Credential)

Named Credentials are the Salesforce-standard mechanism for storing credentials used in outbound HTTP callouts. The modern architecture (API 56.0+) separates the endpoint URL (Named Credential) from the authentication mechanism (External Credential).

**How it works for the API token:**

1. An External Credential defines the `Custom` authentication protocol with a custom `Authorization` header using the merge field `{!$Credential.Replicated_Vendor_Portal.ApiToken}`
2. A Named Credential stores the endpoint URL (`https://api.replicated.com`) and references the External Credential
3. A Principal under the External Credential holds the encrypted token value
4. Access is gated by Permission Sets (External Credential Principal Access)
5. Apex code uses `callout:Replicated_API/vendor/v3/path` instead of hardcoded URLs and manual headers

**Security properties:**

| Property | Behavior |
|---|---|
| Encryption at rest | Yes. Values are write-only — never retrievable via SOQL, API, UI, or debug logs |
| Visible in code/logs | No. Injected server-side at runtime |
| Sandbox isolation | Secrets do NOT propagate on sandbox refresh |
| Access control | Permission Set-gated per Principal |
| Audit trail | Setup Audit Trail logs credential changes; Event Monitoring captures usage |
| Separation of duties | Admin configures credential; developer references by name |
| Version control exposure | Secrets never appear in metadata files — only the structure deploys |
| Token rotation | Update via Setup UI or Connect REST API. Zero code changes |

**Applicability:**
- API token (outbound callout auth): **Direct fit.** This is the primary use case for Named Credentials.
- HMAC webhook secret (inbound signature verification): **Not applicable.** Named Credentials are designed for outbound callout authentication, not for reading secrets in arbitrary Apex logic.

**Developer Edition compatibility:** Named Credentials are a core platform feature available in all editions that support Apex callouts, including Developer Edition. The org already makes HTTP callouts via the existing Remote Site Setting.

**Implementation impact:**
- Create `ExternalCredential` and `NamedCredential` metadata (deployable via SFDX)
- Populate the token value post-deployment via Setup UI or Connect REST API (secrets are excluded from metadata by design)
- Refactor `ReplicatedPlatform.cls`: replace hardcoded endpoints with `callout:Replicated_API/path`, remove manual `Authorization` header, remove constructor dependency on `ReplicatedVendorPortalCredential__mdt`
- Refactor `ReplicatedFulfillment.cls`: remove SOQL query for credential CMT
- Remove `Replicated_Vendor_Portal_API_Credential__mdt` and `ReplicatedVendorPortal.remoteSite-meta.xml`
- Create Permission Set for External Credential Principal Access
- Update `package.xml` to include `NamedCredential` and `ExternalCredential` types

### Option 2: Protected Custom Settings (Hierarchy) with Shield Platform Encryption

Custom Settings support Hierarchy-type settings that can store org-level values. With Shield Platform Encryption (a paid add-on), fields can be encrypted at rest.

**Limitations:**
- Shield Platform Encryption requires an additional Salesforce license — not available on Developer Edition
- Custom Settings do not support `EncryptedText` field types without Shield
- Without Shield, a Protected Custom Setting offers the same security posture as a Protected CMT
- Custom Settings are visible in Setup UI to users with View Setup and Configuration
- Custom Settings values propagate to sandboxes on refresh

**Applicability:** Not viable for the Developer Edition org. Would require Shield license ($X/user/month) for any meaningful security improvement over the current approach.

### Option 3: Keep Current Protected Custom Metadata Types

The current approach stores credentials in Protected CMTs with `DeveloperControlled` field manageability.

**What Protected visibility provides:**
- Not queryable via SOQL from subscriber org code (only same-namespace Apex)
- Not visible in the Custom Metadata Types setup page to non-admin users
- Values are controlled by the developer (require deployment to change)

**What it does NOT provide:**
- Encryption at rest (values are plaintext in the database)
- Protection from admins with Customize Application permission (can read via SOQL in Execute Anonymous)
- Sandbox isolation (values copy on refresh)
- Separation of duties (anyone with org access who can write Apex can read the value)
- Audit trail for credential access

**Acceptability:** Reasonable for a non-production demo/development environment where the threat model is limited to accidental exposure rather than determined adversaries.

## Recommendation

### API Token → Named Credentials (Option 1)

The API token should migrate to Named Credentials. This is the Salesforce-standard approach, provides genuine encryption and access control, works on Developer Edition, and simplifies the Apex code by eliminating manual credential management.

The refactoring also removes the Remote Site Setting (Named Credentials automatically whitelist their endpoint) and eliminates the credential CMT entirely, reducing the metadata surface area.

### HMAC Webhook Secret → Keep Protected CMT (Option 3)

The webhook signing secret should remain in the Protected CMT. Named Credentials don't apply to inbound webhook verification, and Protected Custom Settings offer no security improvement without Shield. The Protected CMT with `DeveloperControlled` manageability is the most appropriate available mechanism for this use case on Developer Edition.

**Documented risks for the HMAC secret:**
- Readable by org admins via SOQL in Execute Anonymous
- Not encrypted at rest without Shield Platform Encryption
- Copies to sandboxes on refresh
- Acceptable for demo/dev; would need Shield or a secrets management integration (e.g., AWS Secrets Manager via callout) for production

## Implementation Guidance

### Named Credential metadata structure

```
create-license/main/default/
  externalCredentials/
    Replicated_Vendor_Portal.externalCredential-meta.xml
  namedCredentials/
    Replicated_API.namedCredential-meta.xml
```

### ExternalCredential XML

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExternalCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Replicated Vendor Portal</label>
    <authenticationProtocol>Custom</authenticationProtocol>
    <externalCredentialParameters>
        <parameterName>Authorization</parameterName>
        <parameterType>HttpHeader</parameterType>
        <parameterValue>{!$Credential.Replicated_Vendor_Portal.ApiToken}</parameterValue>
    </externalCredentialParameters>
    <principals>
        <principalName>NamedPrincipal</principalName>
        <principalType>NamedPrincipal</principalType>
        <sequenceNumber>1</sequenceNumber>
    </principals>
</ExternalCredential>
```

### NamedCredential XML

```xml
<?xml version="1.0" encoding="UTF-8"?>
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <allowMergeFieldsInBody>false</allowMergeFieldsInBody>
    <allowMergeFieldsInHeader>true</allowMergeFieldsInHeader>
    <externalCredential>Replicated_Vendor_Portal</externalCredential>
    <generateAuthorizationHeader>false</generateAuthorizationHeader>
    <label>Replicated API</label>
    <endpoint>https://api.replicated.com</endpoint>
</NamedCredential>
```

### Apex refactoring pattern

```apex
// Before (ReplicatedPlatform.cls)
public ReplicatedPlatform(ReplicatedVendorPortalCredential__mdt credential) {
    this.apiToken = credential.ApiToken__c;
}
// ...
req.setEndpoint('https://api.replicated.com/vendor/v3/customers/search');
req.setHeader('Authorization', this.apiToken);

// After
public ReplicatedPlatform() {
    // No credential needed — Named Credential handles auth
}
// ...
req.setEndpoint('callout:Replicated_API/vendor/v3/customers/search');
// Authorization header injected automatically
```

### Post-deployment: populate the token

The Metadata API excludes secret values by design. After deploying the structure, set the token via:

1. **Setup UI**: External Credential → Principal → edit Authentication Parameter
2. **Connect REST API**: `POST /services/data/v61.0/named-credentials/external-credentials/Replicated_Vendor_Portal/principals/NamedPrincipal`

### Makefile update

The existing `make credentials` target should be updated to use the Connect REST API to populate the Named Credential principal instead of creating/updating the CMT record.

## Security Trade-offs Summary

| Concern | API Token (Named Credentials) | HMAC Secret (Protected CMT) |
|---|---|---|
| Encrypted at rest | Yes | No (requires Shield) |
| Readable by admins | No (write-only) | Yes (SOQL in Execute Anonymous) |
| Sandbox isolation | Yes (excluded from refresh) | No (copies on refresh) |
| Audit trail | Yes (Setup Audit Trail) | No |
| Code separation | Yes (developer never sees token) | No (Apex reads plaintext value) |
| Token rotation | UI/API, no deployment | Requires metadata deployment |
| Acceptable for production | Yes | Only with Shield or documented risk acceptance |

## Related

- [#21](https://github.com/crdant/replicated-salesforce-fulfillment/issues/21) — Evaluate secure secret storage for CMT credentials (this issue)
- [#6](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6) — Event-driven bidirectional sync (parent epic)
- [PR #15](https://github.com/crdant/replicated-salesforce-fulfillment/pull/15) — Define Salesforce data model (changed CMTs to Protected)
- [Salesforce Named Credentials Developer Guide](https://developer.salesforce.com/docs/platform/named-credentials/guide/get-started.html)
- [Ross Belmont's API Key Named Credentials Guide](https://github.com/rossbelmont/named-creds-api-key)
