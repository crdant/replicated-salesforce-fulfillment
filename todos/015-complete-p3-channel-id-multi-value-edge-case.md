---
status: complete
priority: p3
issue_id: "015"
tags:
  - code-review
  - quality
  - shell
dependencies: []
---

# Add first // empty to channel ID jq filter

## Problem Statement

The channel ID lookup (line 28-29) does not use `first // empty`, unlike the app lookup (line 20-21). If multiple channels have the same slug (unlikely but possible through API inconsistency), `channel_id` would contain newline-separated IDs, producing malformed JSON output.

## Findings

**Security Sentinel (MEDIUM-2):** The `jq --arg` flag treats multi-line values as a single string, so the output JSON `channel_id` would contain a newline-concatenated string of IDs. Downstream consumers expecting a single ID would fail. The app lookup already guards against this with `[...] | first // empty`.

## Proposed Solutions

### Option A: Add first // empty (Recommended)
- Match the structural pattern used in the app lookup (line 20-21)
- Defensive hardening against multi-value edge case
- **Effort**: Small (one-line change)
- **Risk**: None

```bash
channel_id=$(echo "$app_match" | jq -r --arg channel "$REPLICATED_CHANNEL" \
  '[.channels[] | select(.channelSlug == $channel) | .id] | first // empty')
```

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Channel ID jq filter uses `first // empty` consistent with app lookup
- [ ] Script outputs a single channel ID value, not multiple

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-18 | Created from PR #49 code review | Structural consistency between similar jq lookups prevents edge case bugs |

## Resources

- PR: #49
- File: `hack/resolve-app-metadata` (lines 28-29 and 20-21)
