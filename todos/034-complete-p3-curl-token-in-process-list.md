---
status: complete
priority: p3
issue_id: "034"
tags:
  - code-review
  - security
  - tooling
dependencies: []
---

# Use heredoc for curl payload to avoid token in process list

## Problem Statement

The `hack/set-api-token` script passes the API token directly in `curl -d` via shell interpolation. This makes the token momentarily visible in the process list (`ps aux`) on multi-user systems. The exposure window is milliseconds and this is a local dev script, but it can be hardened with a one-line change.

## Findings

- **Source**: security-sentinel
- **File**: `hack/set-api-token`, lines 55-68
- Token appears in curl command-line arguments via `${TOKEN}` interpolation in `-d` flag
- The existing `hack/set-webhook-secret` script has the same pattern (pre-existing)
- Not exploitable in single-user dev environments; relevant for shared CI runners

## Proposed Solutions

### Option A: Use heredoc with curl stdin
- Replace `curl -d "{...}"` with `curl -d @- <<EOF`
- Token is passed via stdin, not command-line arguments
- **Effort**: Small
- **Risk**: Low

```bash
curl -s -w "\n%{http_code}" -X PUT "$API_URL" \
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
```

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Token value does not appear in `ps aux` output during script execution
- [ ] Script still sets the credential successfully

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #54 code review | Low severity — dev script, millisecond window |

## Resources

- PR #54: Named Credentials migration
- `hack/set-api-token`: lines 55-68
