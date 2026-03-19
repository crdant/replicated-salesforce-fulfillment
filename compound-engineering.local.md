---
review_agents:
  - compound-engineering:review:security-sentinel
  - compound-engineering:review:architecture-strategist
  - compound-engineering:review:code-simplicity-reviewer
---

Salesforce DX project with bash utility scripts in `hack/`. Apex classes use API version 61.0. Shell scripts use `set -euo pipefail` and depend on `replicated` CLI and `jq`.
