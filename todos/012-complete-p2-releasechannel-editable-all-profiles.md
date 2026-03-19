---
status: complete
priority: p2
issue_id: "012"
tags:
  - code-review
  - security
  - field-level-security
  - pre-existing
dependencies: []
---

# Pre-existing: Product2.ReleaseChannel__c is editable=true on all non-Admin profiles

## Problem Statement

`Product2.ReleaseChannel__c` has `editable=true` on all 6 profiles, including ContractManager, both Marketing profiles, and Support — profiles where every other Product2 custom field is `editable=false`. This field drives the Replicated license fulfillment pipeline via `OrderTerms.channelId()`, so unauthorized edits could alter which release channel a customer license targets.

Both `ReleaseChannel__c` and `Application__c` have `securityClassification=Internal` in their field metadata and both feed into `OrderTerms`. Yet this PR correctly locked down `Application__c` to Admin-only edit, while `ReleaseChannel__c` remains wide open — a pre-existing gap the PR didn't address.

## Findings

- **Security Sentinel**: Medium severity. Non-Admin edit of ReleaseChannel could grant customers wrong release channel access during license creation.
- **Architecture Strategist**: Both `ReleaseChannel__c` and `Application__c` are Internal-classified Replicated identifiers consumed by `OrderTerms`. Inconsistent that one is locked and the other isn't.
- **Pattern Recognition Specialist**: HIGH severity. Only pre-existing Product2 field not locked down. All others are `editable=false` for non-Admin.
- **Agent-Native Reviewer**: Sales profile has `editable=true` — sales users probably should not edit release channel metadata.
- **Learnings Researcher**: `docs/solutions/security-issues/incorrect-fls-pattern-product2-custom-fields.md` documents the convention: model FLS after sibling fields on the same object.

## Proposed Solutions

### Option A: Set editable=false on non-Admin profiles (Recommended)

Change `Product2.ReleaseChannel__c` to `editable=false` on 5 non-Admin profiles. On profiles where `readable=false` already (ContractManager, Marketing), also confirm no readable gap.

- **Pros**: Consistent with Application__c and all other Product2 fields. Closes a real attack vector.
- **Cons**: None
- **Effort**: Small (5 one-line changes in profile XMLs)
- **Risk**: None — non-Admin users should not configure release channels

### Option B: Address in follow-up PR

Track as a separate issue and fix after this PR merges.

- **Pros**: Keeps this PR's scope clean
- **Cons**: Gap persists; this is the security hardening PR where it belongs
- **Effort**: Same as Option A, just later
- **Risk**: Low — pre-existing condition

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files**: All 5 non-Admin profile XMLs, line ~87 in each
- **Field metadata**: `Product2.ReleaseChannel__c` — `securityClassification=Internal`
- **Code path**: `OrderTerms.channelId()` (OrderTerms.cls:81-86) reads this field during license fulfillment

## Acceptance Criteria

- [ ] `Product2.ReleaseChannel__c` has `editable=false` on ContractManager, Custom: Marketing Profile, Custom: Sales Profile, Custom: Support Profile, MarketingProfile
- [ ] Admin profile retains `editable=true`

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review of PR #52 | 4 of 6 review agents independently flagged; pre-existing gap missed by this PR |

## Resources

- PR #52: https://github.com/crdant/replicated-salesforce-fulfillment/pull/52
- `OrderTerms.cls` lines 81-86: `channelId()` method consuming this field
- Convention doc: `docs/solutions/security-issues/incorrect-fls-pattern-product2-custom-fields.md`
