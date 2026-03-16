---
title: Portal invite API receiving installationId instead of customer id
category: integration-issues
date: 2026-03-16
severity: high
component: ReplicatedPlatform.cls, ReplicatedFulfillment.cls
tags: [api-integration, identifier-mismatch, replicated-api, enterprise-portal, apex]
related_issues:
  - "#16"
  - "#8"
---

# Portal invite API receiving installationId instead of customer id

## Problem

The `inviteToPortal()` method in `ReplicatedPlatform.cls` was called with `licenseId` as the `customer_id` parameter. The Replicated API's `Customer` schema has three distinct ID fields:

- `id` -- the customer's unique identifier
- `installationId` -- the license/installation ID, mapped to `licenseId` in code
- `customId` -- a user-defined custom identifier (Salesforce Account ID in this project)

The code was passing `installationId` where the API expected `id`. This was discovered during a multi-agent code review where 3 independent agents (architecture, security, pattern recognition) all flagged the same semantic mismatch.

## Root Cause

`createLicense()` in `ReplicatedPlatform.cls` returned only `created.licenseId` (a String), discarding the full customer object. The caller had no access to `customer.id`. The variable was named `licenseId` in the caller but mapped to parameter `customerId` in the callee -- the naming mismatch masked the bug.

This was confirmed by:

1. The Replicated Vendor API v3 OpenAPI spec from `https://api.replicated.com/vendor/v3/spec/vendor-api-v3.json`
2. The `POST /app/{app_id}/enterprise-portal/customer-user` endpoint which takes `customer_id` in the body
3. The `Customer` schema which has separate `id` and `installationId` fields
4. RBAC policy `kots/app/[:appid]/license/[:customer_id]/read` which further confirmed the semantic distinction

## Solution

1. Changed `createLicense()` return type from `String` to `ReplicatedCustomer` -- returning the full object instead of just `licenseId`
2. Restructured `execute()` to use a single `loadCustomer()` call, branch on null, and access both `customer.id` and `customer.licenseId`
3. Pass `customer.id` (not `customer.licenseId`) to `inviteToPortal()`

**Before:**

```apex
if (!this.platform.customerExists(this.terms)) {
    licenseId = this.platform.createLicense(this.terms);  // returns String (licenseId)
} else {
    customer = this.platform.loadCustomer(this.terms);
    licenseId = customer.licenseId;
}
this.platform.inviteToPortal(appId, licenseId, email);  // BUG: passes licenseId as customerId
```

**After:**

```apex
ReplicatedCustomer customer = this.platform.loadCustomer(this.terms);
if (customer == null) {
    customer = this.platform.createLicense(this.terms);  // returns ReplicatedCustomer
} else {
    customer.updateTerms(this.terms);
    this.platform.updateCustomer(customer);
}
this.platform.inviteToPortal(appId, customer.id, email);  // FIXED: passes customer.id
```

## Prevention Strategies

1. **Return rich domain objects instead of primitives.** When a method extracts data from an external system, return the complete domain object rather than a single field. The original `createLicense()` returned only `String licenseId`, forcing callers to lose access to `customer.id`. Returning the full `ReplicatedCustomer` object lets callers choose the correct field based on the API contract.

2. **Verify API field semantics against OpenAPI specs.** Before integrating with external APIs, consult the OpenAPI specification to understand field meanings. The bug occurred because the code assumed `customer_id` referred to `licenseId` when it actually expected the customer's unique ID.

3. **Standardize naming across layers.** The code used `licenseId` in the caller, `customerId` in the method parameter, and `customer_id` in the API body. This divergence masked the error. Consistent naming makes mismatches visible: calling `inviteToPortal(appId, licenseId, email)` when the parameter is `customerId` immediately signals a problem.

4. **Multi-agent code review catches semantic bugs.** This bug was caught by 3 independent review agents. Semantic issues that a single reviewer might miss become apparent when multiple perspectives analyze the same code.

## Related Documentation

- [Event-Driven Bidirectional Sync Research](../../research/2026-03-16-event-driven-bidirectional-sync.md) -- design decision #7 covers Enterprise Portal invite as a separate API call
- [User Story: Self-Service Trial Workflow](../../User%20Story.md) -- maps capabilities to Replicated features
- PR #16: Refactor fulfillment to use Enterprise Portal invite
- Issue #8: Refactor fulfillment to use Enterprise Portal invite instead of email
- Issue #6: Event-driven bidirectional sync (parent epic)
- [Replicated Enterprise Portal docs](https://docs.replicated.com/vendor/enterprise-portal-self-serve-signup)
- [Replicated Vendor API v3 OpenAPI spec](https://api.replicated.com/vendor/v3/spec/vendor-api-v3.json)
