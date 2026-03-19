---
status: deferred
priority: p3
issue_id: "074"
github_issue: 96
tags:
  - code-review
  - reliability
  - apex
  - validation
dependencies: []
---

# customer_name exceeding field limits rolls back entire direct-create batch

## Problem Statement

The `customer_name` value from the webhook payload is used directly as `Account.Name` (max 255), `Contact.LastName` (max 80), and in `Opportunity.Name` as `name + ' - Trial Conversion'` (max 120, so effective limit is 99 chars). If any `customer_name` exceeds the shortest limit (80 chars), the DML throws `DmlException`, and the savepoint at line 191 rolls back ALL direct-create records in the batch — not just the offending event.

## Findings

- **Security Sentinel**: Flagged as Medium — one bad record causes batch-wide silent data loss.

## Proposed Solutions

### Option A: Truncate customer_name to safe length (Recommended)

```apex
String customerName = (String) data.get('customer_name');
String name = String.isNotBlank(customerName) ? customerName.left(80) : 'Unknown';
```

- Pros: Simple, prevents batch failure from one oversized name
- Cons: Truncated names lose information
- Effort: Small
- Risk: None

## Technical Details

- **Affected files**: `create-license/main/default/classes/EpUserJoinedHandler.cls` lines 183-184, 202-203, 219-220
- **Database changes**: None

## Acceptance Criteria

- [ ] `customer_name` truncated to 80 chars (Contact.LastName limit)
- [ ] Existing tests continue to pass

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-19 | Created | Code review finding — security sentinel |

## Resources

- PR: #91
- File: `EpUserJoinedHandler.cls` lines 183-184, 202-203, 219-220
