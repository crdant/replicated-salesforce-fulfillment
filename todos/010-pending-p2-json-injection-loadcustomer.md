---
status: pending
priority: p2
issue_id: "010"
tags:
  - code-review
  - security
  - apex
dependencies: []
---

# Replace string concatenation with JSON.serialize in loadCustomer

## Problem Statement

`ReplicatedPlatform.loadCustomer()` builds its HTTP request body via string concatenation rather than `JSON.serialize()`. If `terms.applicationId()` or `terms.accountId()` ever contain characters like `"`, `\`, or `}`, they would break JSON structure or inject arbitrary keys. The same class already uses `JSON.serialize()` correctly in `inviteToPortal()`.

## Findings

**File:** `create-license/main/default/classes/ReplicatedPlatform.cls:18`

```apex
String query = 'customId:' + terms.accountId();
String requestBody = '{"app_id":"' + terms.applicationId() + '","query":"' + query + '","include_paid":true,"include_active":true,"include_inactive":true}';
```

Current exploitability is low (values come from Salesforce IDs and controlled custom fields), but the pattern is fragile and inconsistent with the safer approach used elsewhere in the same class.

## Proposed Solutions

### Option A: Use JSON.serialize with Map (Recommended)
- Replace string concatenation with `Map<String, Object>` + `JSON.serialize()`
- Consistent with `inviteToPortal()` pattern already in the class
- **Effort**: Small
- **Risk**: None

```apex
Map<String, Object> body = new Map<String, Object>();
body.put('app_id', terms.applicationId());
body.put('query', 'customId:' + terms.accountId());
body.put('include_paid', true);
body.put('include_active', true);
body.put('include_inactive', true);
req.setBody(JSON.serialize(body));
```

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] `loadCustomer()` uses `JSON.serialize()` for request body construction
- [ ] No string concatenation used for JSON body building in `ReplicatedPlatform.cls`

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from code review — pre-existing issue, not introduced by this PR | inviteToPortal() already uses the safe pattern |

## Resources

- File: `create-license/main/default/classes/ReplicatedPlatform.cls`
- OWASP: Injection vulnerabilities
