---
title: "Migrate API token from Custom Metadata Type to Named Credentials"
category: security-issues
date: 2026-03-18
severity: high
tags:
  - named-credentials
  - external-credentials
  - security
  - credential-migration
  - apex
  - shell-scripting
components:
  - ReplicatedPlatform.cls
  - ReplicatedFulfillment.cls
  - hack/set-api-token
  - Replicated_API.namedCredential-meta.xml
  - Replicated_Vendor_Portal.externalCredential-meta.xml
  - Replicated_API_Access.permissionset-meta.xml
  - destructiveChangesPost.xml
related_issues:
  - "#28"
  - "#21"
  - "PR #54"
---

# Migrate API Token from Custom Metadata Type to Named Credentials

## Problem

The Replicated Vendor Portal API token was stored as a plaintext `Text(100)` field in a Custom Metadata Type (`Replicated_Vendor_Portal_API_Credential__mdt`). The secret was queryable via SOQL by any user with metadata read access, visible in Setup UI, and included unencrypted in metadata deployments. Apex code queried the token via SOQL, passed it as a constructor argument, stored it in a class field, and manually set it on every outbound HTTP request via `setHeader('Authorization', ...)`.

Named Credentials are the Salesforce-standard mechanism for outbound callout authentication. They encrypt credentials at rest, inject headers at the HTTP transport layer, restrict access through Permission Set assignments, and keep credential values invisible to Apex code.

## Investigation

A code review of the migration (PR #54) identified five findings across two priority levels, all resolved in the same session:

**P2 Findings:**
1. **Permission Set assignment not automated.** The `Replicated_API_Access` Permission Set must be assigned to the integration user for callouts to work, but no Makefile target or README step existed. Resolution: added `make permissions` target and README step.
2. **Shell script missing defensive options.** `hack/set-api-token` lacked `set -euo pipefail` and made duplicate `sf org display` calls. Resolution: added defensive options, consolidated calls, initialized variables for `set -u` compatibility.

**P3 Findings:**
3. Token visible in process list via `curl -d` — switched to heredoc stdin (`-d @-`).
4. Explicit empty constructor in `ReplicatedPlatform.cls` — removed (Apex provides implicit no-arg constructor).
5. Deployment gap between `make deploy` and `make credentials` undocumented — added note in README.

## Solution

### Architecture Change

**Before:**
```
ReplicatedFulfillment constructor
  → SOQL: Replicated_Vendor_Portal_API_Credential__mdt
  → new ReplicatedPlatform(credential)
    → this.apiToken = credential.ApiToken__c
    → req.setEndpoint('https://api.replicated.com/...')
    → req.setHeader('Authorization', this.apiToken)
```

**After:**
```
ReplicatedFulfillment constructor
  → new ReplicatedPlatform()
    → req.setEndpoint('callout:Replicated_API/...')
    → // Authorization header injected by Salesforce runtime
```

### Step 1: External Credential

Defines *how* to authenticate. Uses `Custom` protocol with an `HttpHeader` parameter that injects the token via a merge field.

`create-license/main/default/externalCredentials/Replicated_Vendor_Portal.externalCredential-meta.xml`:

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

- `Custom` protocol because the Replicated API uses a bare token in the `Authorization` header (not OAuth, not Basic).
- `NamedPrincipal` means a single shared credential (service account pattern), not per-user authentication.
- The merge field `{!$Credential.Replicated_Vendor_Portal.ApiToken}` resolves at runtime to the encrypted stored value.

### Step 2: Named Credential

Defines *where* to call and links to the External Credential for auth.

`create-license/main/default/namedCredentials/Replicated_API.namedCredential-meta.xml`:

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

- `generateAuthorizationHeader` must be `false` — the External Credential handles the header. Setting `true` causes a conflicting auto-generated header.
- `allowMergeFieldsInHeader` must be `true` — required for the `{!$Credential...}` merge field to resolve. Without it, the merge field is sent as a literal string.

### Step 3: Permission Set

`create-license/main/default/permissionsets/Replicated_API_Access.permissionset-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Grants access to the Replicated Vendor Portal API via the Replicated_API Named Credential.</description>
    <hasActivationRequired>false</hasActivationRequired>
    <label>Replicated API Access</label>
    <externalCredentialPrincipalAccesses>
        <enabled>true</enabled>
        <externalCredentialPrincipal>Replicated_Vendor_Portal.NamedPrincipal</externalCredentialPrincipal>
    </externalCredentialPrincipalAccesses>
</PermissionSet>
```

The `externalCredentialPrincipal` value follows the format `{ExternalCredentialName}.{PrincipalName}`. Without this permission set assigned, callouts fail at runtime with a generic authorization error.

### Step 4: Refactor Apex

**ReplicatedPlatform.cls** — Remove token field, constructor parameter, all `setHeader('Authorization', ...)` calls. Replace hardcoded URLs with `callout:` prefix:

```apex
public class ReplicatedPlatform {

    public ReplicatedCustomer loadCustomer(OrderTerms terms) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Replicated_API/vendor/v3/customers/search');
        req.setMethod('POST');
        req.setHeader('accept', 'application/json');
        req.setHeader('content-type', 'application/json');
        // No Authorization header — Named Credential injects it
        // ...
    }
    // Same pattern for createLicense, updateCustomer, getLicenseFile, inviteToPortal
}
```

**ReplicatedFulfillment.cls** — Remove SOQL query, use no-arg constructor:

```apex
public ReplicatedFulfillment(OrderTerms terms) {
    this.terms = terms;
    this.platform = new ReplicatedPlatform();
}
```

### Step 5: Provisioning Script

The Metadata API excludes secret values by design. Provision the token via the Connect REST API.

`hack/set-api-token`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ORG_ALIAS=""
TOKEN=""
# ... getopts parsing ...

ORG_INFO=$(sf org display --target-org "$ORG_ALIAS" --json)
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')
ACCESS_TOKEN=$(echo "$ORG_INFO" | jq -r '.result.accessToken')

API_URL="${INSTANCE_URL}/services/data/v61.0/named-credentials/external-credentials/Replicated_Vendor_Portal/principals/NamedPrincipal"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$API_URL" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
    "principalName": "NamedPrincipal",
    "principalType": "NamedPrincipal",
    "authenticationParameters": [
        {
            "parameterName": "ApiToken",
            "parameterValue": "${TOKEN}",
            "parameterType": "AuthProviderParameter"
        }
    ]
}
EOF
)
```

Key details:
- Uses `-d @-` with heredoc to keep the token out of the process list.
- The `parameterName` (`ApiToken`) must match the merge field suffix in the External Credential.
- Single `sf org display` call, parsed twice with `jq`.

### Step 6: Destructive Changes

`destructiveChangesPost.xml` removes old CMT and Remote Site Setting *after* new code deploys:

```xml
<types>
    <members>Replicated_Vendor_Portal_API_Credential__mdt</members>
    <name>CustomObject</name>
</types>
<types>
    <members>ReplicatedVendorPortal</members>
    <name>RemoteSiteSetting</name>
</types>
```

Must be `destructiveChangesPost` (not `Pre`) — the old code still references the CMT until the new code replaces it in the same deployment.

### Step 7: Deployment Sequence

```bash
make deploy       # Deploy new code + metadata, delete old CMT + Remote Site Setting
make permissions  # Assign Permission Set to running user
make credentials  # Provision API token via Connect REST API
```

## Configuration Gotchas

1. **`generateAuthorizationHeader` must be `false`** — Otherwise Salesforce generates a conflicting `Authorization` header.
2. **`allowMergeFieldsInHeader` must be `true`** — Otherwise the `{!$Credential...}` merge field is sent as a literal string.
3. **Permission Set assignment is required** — Deploying the credential metadata is not enough. The running user must have `Replicated_API_Access` assigned.
4. **Secret values excluded from Metadata API** — The `parameterValue` in the External Credential XML is the merge field template, not the secret. The real token must be provisioned via the Connect REST API.
5. **`parameterName` alignment** — The name `ApiToken` must match exactly in the External Credential merge field and the Connect REST API provisioning call.
6. **No Remote Site Setting needed** — Named Credentials act as their own callout allowlist. The old Remote Site Setting should be actively removed.

## Prevention

### Credential Storage Decision Checklist

| Question | Yes → | No → |
|----------|-------|------|
| Is this for outbound callouts only? | Named Credential | Continue below |
| Does Apex need to read the raw value? | Protected CMT | Named Credential |
| Must it be deployable via Metadata API? | Protected CMT | Named Credential |
| Is it for inbound request validation (HMAC, signatures)? | Protected CMT | Named Credential |

### Future Credential Migration Checklist

- [ ] Identify every Apex class referencing the old credential storage
- [ ] Determine if credential is outbound (Named Credential) or inbound (Protected CMT)
- [ ] Create External Credential, Named Credential, Permission Set metadata
- [ ] Update Apex to use `callout:` endpoint pattern
- [ ] Script post-deploy provisioning via Connect REST API
- [ ] Script Permission Set assignment
- [ ] Add `destructiveChangesPost.xml` (not Pre) for old metadata removal
- [ ] Update `package.xml`, README, CLAUDE.md
- [ ] Test end-to-end in scratch org with provisioned credentials

### Shell Scripting Best Practices for Credential Scripts

- Always start with `set -euo pipefail`
- Initialize variables before use (for `set -u` compatibility)
- Never pass secrets via command-line arguments — use heredoc stdin (`-d @-`)
- Consolidate CLI calls (one `sf org display`, parse multiple fields)
- Validate HTTP response codes before proceeding

## Related Documentation

- [`docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md`](../security-issues/secret-storage-evaluation-for-cmt-credentials.md) — The evaluation that preceded this migration. Compares Named Credentials, Protected Custom Settings with Shield, and Protected CMT. Recommends Named Credentials for the API token; Protected CMT for the HMAC webhook secret.
- [`docs/research/2026-03-16-secret-storage-evaluation.md`](../../research/2026-03-16-secret-storage-evaluation.md) — Full research document with implementation guidance, metadata XML examples, and security trade-offs comparison.
- [`docs/solutions/integration-issues/salesforce-data-model-review-hardening.md`](../integration-issues/salesforce-data-model-review-hardening.md) — Data model review that first identified credential CMTs with Public visibility as a security concern (the finding that triggered issue #21).
- [`docs/solutions/workflow/incomplete-cmt-object-rename-in-docs.md`](../workflow/incomplete-cmt-object-rename-in-docs.md) — Lesson about stale references after renaming the CMT (applies to removal as well).
- [`docs/solutions/integration-issues/wrong-identifier-type-in-api-call.md`](../integration-issues/wrong-identifier-type-in-api-call.md) — Prior refactoring of the same Apex classes (`ReplicatedPlatform`, `ReplicatedFulfillment`).
- [Issue #28](https://github.com/crdant/replicated-salesforce-fulfillment/issues/28) — Implementation issue for the Named Credentials migration.
- [Issue #21](https://github.com/crdant/replicated-salesforce-fulfillment/issues/21) — Evaluation issue that preceded #28.
- [PR #54](https://github.com/crdant/replicated-salesforce-fulfillment/pull/54) — The pull request implementing this migration.
