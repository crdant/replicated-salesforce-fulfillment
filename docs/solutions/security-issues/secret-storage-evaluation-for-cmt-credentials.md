---
title: Secret storage evaluation for Custom Metadata Type credentials
category: security-issues
date: 2026-03-17
tags:
  - salesforce
  - security
  - secret-management
  - custom-metadata-type
  - named-credentials
  - encryption
components:
  - Replicated_Vendor_Portal_API_Credential__mdt
  - Replicated_Webhook_Secret__mdt
  - ReplicatedPlatform
  - ReplicatedFulfillment
severity: high
resolution_time: 1 session
pr: 27
issues: [21, 28]
---

# Secret Storage Evaluation for Custom Metadata Type Credentials

Evaluated three approaches for securing credentials stored as plaintext Text fields in Protected Custom Metadata Types. Recommended Named Credentials for the API token and keeping the Protected CMT for the HMAC webhook secret, with documented trade-offs for each.

## Problem

Two Custom Metadata Types store sensitive credentials as plaintext:

- `Replicated_Vendor_Portal_API_Credential__mdt.ApiToken__c` — Vendor Portal API token (Text, 100)
- `Replicated_Webhook_Secret__mdt.Secret__c` — HMAC-SHA256 signing secret (Text, 255)

PR #15 changed both to `Protected` visibility, limiting SOQL access to same-namespace Apex code. But Protected visibility does not provide encryption at rest, sandbox isolation, audit trails, or separation of duties. Admin users with Customize Application permission can still read the plaintext values via Execute Anonymous.

## Root Cause

Custom Metadata Types are designed for configuration data, not secrets. Their visibility controls manage discoverability in the Setup UI but do not encrypt stored values or prevent programmatic access by privileged users. Salesforce CMTs do not support the `EncryptedText` field type.

## Solution

### API Token → Named Credentials

Named Credentials (External Credential + Named Credential, API 56.0+) are the Salesforce-standard mechanism for outbound API authentication. The platform encrypts the credential at rest, injects it server-side at callout time, and never exposes the value via SOQL, API, UI, or debug logs.

**Before** (plaintext CMT):
```apex
// ReplicatedFulfillment.cls
Replicated_Vendor_Portal_API_Credential__mdt cred = [
    SELECT ApiToken__c
    FROM Replicated_Vendor_Portal_API_Credential__mdt
    WHERE DeveloperName = 'Default'
    LIMIT 1
];
this.platform = new ReplicatedPlatform(cred);

// ReplicatedPlatform.cls
req.setEndpoint('https://api.replicated.com/vendor/v3/customers/search');
req.setHeader('Authorization', this.apiToken);
```

**After** (Named Credential):
```apex
// ReplicatedFulfillment.cls — no credential query needed
this.platform = new ReplicatedPlatform();

// ReplicatedPlatform.cls
req.setEndpoint('callout:Replicated_API/vendor/v3/customers/search');
// Authorization header injected automatically by the platform
```

The migration also eliminates the Remote Site Setting (`ReplicatedVendorPortal.remoteSite-meta.xml`) since Named Credentials automatically whitelist their endpoint.

**Implementation deferred to issue #28.**

### HMAC Webhook Secret → Keep Protected CMT

Named Credentials only apply to outbound callout authentication. The HMAC signing secret is used for inbound webhook signature verification (`Crypto.generateMac('HmacSHA256', ...)`) and has no Named Credential equivalent.

Protected Custom Settings offer no security improvement over Protected CMTs without Shield Platform Encryption, which requires a paid add-on not available on the Developer Edition org.

**Documented risks:**
- Readable by org admins via SOQL in Execute Anonymous
- Not encrypted at rest without Shield Platform Encryption
- Copies to sandboxes on refresh
- Acceptable for dev/demo environments; would need Shield or an external secrets manager for production

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| API token storage | Named Credentials | Salesforce-standard, encrypted, access-controlled, audited, works on Developer Edition |
| HMAC secret storage | Protected CMT (status quo) | Named Credentials not applicable to inbound use; no better platform option without Shield |
| Implementation scope | Document now, implement later | Evaluation branch (`docs/`); implementation deferred to #28 |

## Prevention

### Credential Storage Decision Checklist

- [ ] **Outbound API authentication?** Use Named Credentials — never store tokens in CMTs, Custom Settings, or Apex constants
- [ ] **Inbound webhook secret?** Use Protected CMT with `DeveloperControlled` manageability; document the risk acceptance
- [ ] **Public configuration?** (endpoints, app IDs) Regular CMT or Custom Setting — plaintext is acceptable
- [ ] **Can the secret be rotated?** Named Credentials support UI/API rotation with zero code changes; CMTs require metadata deployment
- [ ] **Is the credential in version control?** Named Credential secrets are excluded from metadata by design; CMT values appear in source

### Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|---|---|---|
| API tokens in CMT Text fields | Plaintext, SOQL-readable, copies to sandboxes | Named Credentials |
| Secrets in Apex constants | Compiled into org, visible in git history | Runtime retrieval from Named Credentials or Protected CMT |
| Mixing config and secrets in one CMT | One leaked record exposes everything | Separate objects by sensitivity level |
| No rotation schedule for rotatable secrets | Leaked token = indefinite access | Document rotation frequency; Named Credentials simplify rotation |
| Committing credential values to git | Persists in history even after deletion | `.gitignore` credential files; Named Credentials exclude secrets from metadata |

## Related

- [PR #27](https://github.com/crdant/replicated-salesforce-fulfillment/pull/27) — Evaluation document PR
- [#21](https://github.com/crdant/replicated-salesforce-fulfillment/issues/21) — Evaluate secure secret storage (this evaluation)
- [#28](https://github.com/crdant/replicated-salesforce-fulfillment/issues/28) — Implement Named Credentials migration (follow-up)
- [#6](https://github.com/crdant/replicated-salesforce-fulfillment/issues/6) — Event-driven bidirectional sync (parent epic)
- [PR #15](https://github.com/crdant/replicated-salesforce-fulfillment/pull/15) — Changed CMTs to Protected visibility
- [salesforce-data-model-review-hardening](../integration-issues/salesforce-data-model-review-hardening.md) — PR #15 code review findings (Fixes 7 & 8)
- [2026-03-16-secret-storage-evaluation.md](../../research/2026-03-16-secret-storage-evaluation.md) — Full research document with implementation guidance
