---
status: complete
priority: p2
issue_id: "002"
tags:
  - code-review
  - security
  - field-level-security
  - least-privilege
dependencies: []
---

# Non-Admin profiles grant readable=true on all fields despite least privilege precedent

## Problem Statement

All 5 non-Admin profiles have `readable=true` for all 10 `Replicated_Instance__c` fields. However, the existing `Product2` FLS on non-Admin profiles uses a more restrictive pattern — 4 of 5 Product2 fields are `readable=false` on ContractManager and other non-Admin profiles.

This means Marketing, ContractManager, and MarketingProfile users can see infrastructure details (`K8s_Distribution__c`, `Cloud_Provider__c`, `Instance_Id__c`) and usage metrics (`Daily_Active_Users__c`, `Monthly_Active_Users__c`) they likely have no business need for.

## Findings

- **Security Sentinel**: Violates principle of least privilege. Marketing and ContractManager profiles don't need access to infrastructure fields.
- **Existing pattern**: Product2 fields like `IsAddOn__c`, `IsAdminConsoleEnabled__c` are `readable=false` on non-Admin profiles — technical fields hidden from non-technical roles.

## Proposed Solutions

### Option A: Role-based read access (Recommended)
- Restrict `readable` per role based on business need
- Sales: Account, Status, usage metrics, check-in times (need customer context)
- Support: All fields (need troubleshooting data)
- Marketing: Account, Status, usage metrics (need aggregate data)
- ContractManager: Account, Status only (contractual context)
- **Pros**: Follows least privilege, matches Product2 precedent
- **Cons**: More complex to maintain, different blocks per profile
- **Effort**: Medium (modify 4-5 profiles with per-field readable values)
- **Risk**: Low — may need adjustment as roles clarify

### Option B: Accept as-is
- All profiles can read all fields
- Instance data is not sensitive (infrastructure metadata)
- Simplifies maintenance (all non-Admin profiles identical)
- **Pros**: Simple, easy to maintain
- **Cons**: Doesn't match Product2 precedent, broader access than needed
- **Effort**: None
- **Risk**: None (read-only access to non-sensitive metadata)

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: 5 non-Admin profile-meta.xml files
- **Precedent**: ContractManager Product2 fields `IsAddOn__c`, `IsAdminConsoleEnabled__c`, `IsAirgapEnabled__c`, `IsEmbeddedClusterEnabled__c` are all `readable=false`

## Acceptance Criteria

- [ ] Readable permissions for Replicated_Instance__c fields reflect agreed access model
- [ ] Documentation updated if access model differs from current "all readable" approach

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-16 | Created from code review of PR #25 | Inconsistency with Product2 FLS pattern identified by security-sentinel |

## Resources

- PR #25: https://github.com/crdant/replicated-salesforce-fulfillment/pull/25
