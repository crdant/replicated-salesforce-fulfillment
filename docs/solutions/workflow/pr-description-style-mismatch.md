---
title: PR description style mismatch between agent output and project convention
category: workflow
date: 2026-03-16
updated: 2026-03-19
severity: medium
tags: [pr-writing, agent-expectations, documentation, conventions, recurring]
components: [pull-requests, pull-request-author-agent, documentation]
root_cause: Agents default to a Summary + bullet list template that doesn't match the project's TL;DR + Details setext underline format with narrative prose
---

# PR Description Style Mismatch Between Agent Output and Project Convention

## Problem

Agents generate PR descriptions in a `## Summary` + bullet list format. The project uses `TL;DR` + `Details` with setext underlines and narrative prose paragraphs. This has recurred twice — first with PRs based on the pull-request-author agent defaults, and again with PR #70 where the description was auto-generated in the wrong format.

Agent output (wrong):
```
## Summary
- Adds make setup-replicated orchestrator target
- Creates .env.example documenting all required environment variables
- Adds a "Replicated Platform Setup" section to the README

Closes #47

## Test plan
- [ ] Verify make setup-replicated invokes all four targets
- [ ] Confirm .env.example contains all variables
```

Project convention (correct):
```
TL;DR
-----

Adds a make setup-replicated orchestrator target that runs channels,
enterprise-portal, entitlements, and webhook-subscription in guaranteed
sequence, creates .env.example documenting every environment variable
the project consumes, and documents the setup workflow in the README.

Closes #47

Details
-------

Introduces a setup-replicated Makefile target that invokes four
sub-targets via $(MAKE) recipe calls rather than Make prerequisites...

## Test plan

- [x] make -n setup-replicated prints four sequential $(MAKE) invocations
- [x] .env.example contains every variable referenced by Makefile targets
```

## Root Cause

The style evolved across two eras of PRs but was never fully codified:

- **PRs #1-5** (@crdant): Established TL;DR + Details with setext underlines, narrative prose, no test plan section, no footer.
- **PRs #48-67** (Claude-authored): Kept TL;DR + Details setext format but added `## Test plan` with `- [x]` verified items and a `Generated with Claude Code` footer.

The original solution doc (2026-03-16) only captured the PRs #1-5 style and incorrectly stated "No test plan section" and "No emoji footer." When agents generated PR #70, neither the outdated doc nor the agent defaults produced the correct format.

## The Definitive Style

Established across PRs #1-67. All rules are non-negotiable.

### Template

```markdown
TL;DR
-----

[One prose paragraph. No bullets. Active voice. 50-150 words.]

Closes #XX

Details
-------

[First sentence directly states what the code does — not background.]

[Additional paragraphs explaining design decisions, implications, and
technical details. Active voice throughout. Never use "the PR" or
"the changes" as a subject.]

## Test plan

- [x] [Verified action — what was tested and result]
- [x] [Verified action — what was tested and result]

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Hard Rules

1. **TL;DR and Details use setext underlines** (`-----` / `-------`), NOT ATX `##` headings.
2. **`## Test plan` is the one exception** — uses ATX heading.
3. **TL;DR is one prose paragraph** — no bullets, no lists, no line breaks.
4. **Details is multiple narrative paragraphs** — no bullets, no lists.
5. **`Closes #XX` goes between TL;DR and Details.**
6. **First sentence of Details states what the code does** — lead with action, not background.
7. **Active voice throughout** — never passive ("was deployed", "is rejected").
8. **Never refer to the PR as a subject** — no "The fix removes...", "This PR adds...". State what happens directly.
9. **Test items use `- [x]`** (verified), never `- [ ]` (unchecked). PRs describe what was done, not what will be done.
10. **Content must be accurate** — never reference targets, files, or features that don't exist in the code.
11. **Footer**: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

### Verification Checklist

Before submitting any PR description:

- [ ] TL;DR uses setext underline, not `##`
- [ ] TL;DR is one prose paragraph with no bullets
- [ ] `Closes #XX` between TL;DR and Details
- [ ] Details uses setext underline, not `##`
- [ ] Details first sentence states what code does (not background)
- [ ] No bullets in TL;DR or Details
- [ ] Active voice throughout
- [ ] No "the PR" / "the changes" / "this change" as subject
- [ ] All test items are `- [x]` with verified results
- [ ] All referenced make targets / files / features exist in the code
- [ ] Footer present

## Solution

When writing or reviewing PR descriptions:

1. Follow the template above exactly
2. Read 2-3 recent merged PRs if unsure about voice or tone
3. Convert any bullet lists to narrative prose
4. Verify all referenced targets exist: `grep -oP 'make \K[a-z-]+' <<< "$body" | while read t; do grep -q "^$t:" Makefile || echo "MISSING: $t"; done`
5. Check test items describe past actions (verified), not future plans

## Prevention

The style is documented in three places — keep them consistent:

- **MEMORY.md** (lines 21-33): Agent-facing format reference
- **This file**: Full style guide with template and checklist
- **Merged PRs #48-67**: Living examples of the correct format

When the style evolves again (e.g., a new required section), update all three.

## Related

- PR #70: Second occurrence — description rewritten via `gh pr edit`
- PRs #48-67: Current style reference (Claude-authored, with test plan and footer)
- PRs #1-5: Original style baseline (@crdant, without test plan or footer)
- `docs/solutions/integration-issues/branch-naming-convention-rework.md`: Same theme — implicit conventions need documentation
- `docs/solutions/workflow/incomplete-cmt-object-rename-in-docs.md`: Stale docs causing downstream errors
