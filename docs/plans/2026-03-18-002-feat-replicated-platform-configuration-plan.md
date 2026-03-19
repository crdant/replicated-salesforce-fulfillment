---
title: "feat: Automate Replicated Platform configuration for self-service trial workflow"
type: feat
status: active
date: 2026-03-18
---

# feat: Automate Replicated Platform configuration for self-service trial workflow

## Overview

Adds Makefile targets and `hack/` scripts to configure the Replicated Platform side of the self-service trial workflow described in `docs/User Story.md`. Covers channel setup, Enterprise Portal enablement, trial signup configuration, custom license field creation, webhook subscription, and webhook verification. Everything is repeatable — a user provides their app slug plus an API token (or logged-in `replicated` CLI) and runs `make` targets.

## Problem Statement / Motivation

The project's Salesforce side (issues #6–#13) assumes a fully configured Replicated Platform: webhooks delivering events, Enterprise Portal accepting signups, channels assigned to trial licenses. None of that configuration is scripted today. Without it, a user cloning this repo can deploy the Salesforce metadata but has no way to stand up the Replicated integration end. The demo is incomplete.

## Proposed Solution

Add Makefile targets that configure the Replicated Platform using the `replicated` CLI and Vendor API v3.

### What can be automated

| Configuration | Mechanism |
|---|---|
| Verify app and resolve IDs | `replicated app ls --output json` (existing pattern in `hack/import`) |
| Create/verify release channel | `replicated channel create` / `replicated channel ls` |
| Enable Enterprise Portal | `replicated api put /v3/app/{app_id}/enterprise-portal/status` |
| Enable trial signup | `replicated api put /v3/app/{app_id}/trial-signup` |
| Configure trial signup defaults | `replicated api put /v3/app/{app_id}/trial-signup-settings` |
| Create custom license fields | `replicated api post /v3/app/{app_id}/license-field` |
| Create webhook subscription | `replicated api post /v3/notification_subscription` (undocumented but functional) |
| Verify webhook delivery | `hack/test-webhook` (already exists) |

## Technical Considerations

### Environment variables

New variables for `.env` (loaded via `direnv`):

```bash
# Existing
ORG_ALIAS=shortrib
REPLICATED_APP=slackernews-mackerel
REPLICATED_CHANNEL=unstable
REPLICATED_WEBHOOK_SECRET=adequately-wholly-locally-cleanly-secure-lobster

# New
REPLICATED_TRIAL_EXPIRATION_DAYS=30
REPLICATED_SITE_URL=https://<site-domain>/services/apexrest/replicated/webhook
```

`REPLICATED_API_TOKEN` is inherited from the `replicated` CLI's login session or set via the standard env var the CLI already reads. No need to add it to `.env`.

### App/channel ID resolution

Follow the existing `hack/import` pattern: call `replicated app ls --output json`, pipe through `jq` to resolve `app_id` and `channel_id` from the slug and channel name in env vars. Extract this into a shared helper (`hack/resolve-app-metadata`) so every script doesn't repeat the lookup.

### API authentication

The `replicated api` subcommand uses the same auth as `replicated` CLI — either `REPLICATED_API_TOKEN` env var or `~/.replicated/config`. No separate token handling needed.

### Idempotency

Every target should be safe to run multiple times:
- Channel creation: check if channel exists first, skip if present
- License field creation: the API returns 409 if a field with the same name exists; handle gracefully
- Enterprise Portal/trial signup: PUT endpoints are idempotent by nature
- Webhook subscription: list existing subscriptions, skip if one with the same name exists

## Acceptance Criteria

### Makefile targets

- [ ] `make setup-replicated` — orchestrator target that runs all Replicated configuration in order
- [ ] `make channels` — creates or verifies the release channel specified in `REPLICATED_CHANNEL`
- [ ] `make enterprise-portal` — enables Enterprise Portal and trial signup with default license policy
- [ ] `make entitlements` — creates custom license fields (`member_count_max`) for the app (idempotent)
- [ ] `make webhook-subscription` — creates the event notification subscription with webhook URL and signing secret (idempotent)
- [ ] `make verify-webhook` — confirms the webhook subscription is active and delivering to the Salesforce endpoint
- [ ] `make verify-replicated` — runs all verification checks (channel exists, portal enabled, webhook responding)

### hack/ scripts

- [ ] `hack/resolve-app-metadata` — shared helper that resolves `app_id`, `channel_id`, and `app_name` from env vars; outputs JSON (used by 3+ targets)
- [ ] `hack/setup-enterprise-portal` — enables Enterprise Portal, trial signup, and configures trial signup settings (three API calls with resolved IDs and JSON body construction — too much interpolation to inline readably)
- [ ] `hack/setup-webhook-subscription` — creates the event notification subscription via the undocumented `POST /v3/notification_subscription` endpoint (JSON body with 8 event configs, interpolated URL, and secret — same justification as `setup-enterprise-portal`)

### Cleanup

- [ ] `make replicated-clean` — deletes the webhook subscription on the Replicated side

### Environment and documentation

- [ ] `.env.example` file added with all required variables (no secrets, placeholder values)
- [ ] README updated with Replicated setup section referencing `make setup-replicated`

## Implementation Details

### `hack/resolve-app-metadata`

Extracts the repeated `replicated app ls | jq` pattern from `hack/import` into a reusable helper. Called by `hack/setup-enterprise-portal` and inlined Makefile targets that need `app_id` or `channel_id`.

```bash
#!/usr/bin/env bash
set -euo pipefail
# Outputs JSON: {"app_name": "...", "app_id": "...", "channel_id": "..."}
replicated app ls --output json | jq --arg app "$REPLICATED_APP" --arg channel "$REPLICATED_CHANNEL" \
  '.[] | select(.app.slug == $app) | {
    app_name: .app.name,
    app_id: .app.id,
    channel_id: (.channels[] | select(.channelSlug == $channel) | .id)
  }'
```

### `hack/setup-enterprise-portal`

Three sequential API calls with resolved IDs and JSON body construction — too much shell interpolation to inline readably.

1. `PUT /v3/app/{app_id}/enterprise-portal/status` → `{"status": "always"}`
2. `PUT /v3/app/{app_id}/trial-signup` → `{"enabled": true}`
3. `PUT /v3/app/{app_id}/trial-signup-settings` →

```json
{
  "defaultChannelId": "<resolved from REPLICATED_CHANNEL>",
  "licenseType": "trial",
  "expirationDays": 30,
  "helmInstallEnabled": true,
  "embeddedClusterEnabled": false,
  "isHelmAirgapEnabled": false,
  "supportBundleUploadEnabled": true
}
```

The `defaultChannelId` is resolved at runtime via `hack/resolve-app-metadata`. `expirationDays` defaults to `REPLICATED_TRIAL_EXPIRATION_DAYS` (30 if unset). Self-service signups inherit custom license field defaults from the `member_count_max` field definition.

### Entitlements note

The codebase uses two categories of entitlements:

**Built-in license fields (no setup needed):** `is_airgap_enabled`, `is_snapshot_supported`, `is_support_bundle_upload_enabled`, `is_embedded_cluster_download_enabled`, `is_kots_install_enabled`, `is_disaster_recovery_supported`. These are top-level booleans on the customer create API (`ReplicatedCustomer.cls:35-43`) and handled by CLI flags like `--airgap`, `--snapshot`.

**Custom license fields (must be created):** Only `member_count_max` (Integer, default 100, from `OrderTerms.cls:127`). Created by the `make entitlements` target. Additional custom fields can be added as the demo evolves.

### Makefile additions

```makefile
setup-replicated: channels enterprise-portal entitlements webhook-subscription

channels:
	@id=$$(replicated channel ls --app "$${REPLICATED_APP}" --output json | \
	  jq -r --arg ch "$${REPLICATED_CHANNEL}" '.[] | select(.channelSlug == $$ch) | .id'); \
	if [ -n "$$id" ]; then echo "Channel '$${REPLICATED_CHANNEL}' exists ($$id)"; \
	else replicated channel create --app "$${REPLICATED_APP}" --name "$${REPLICATED_CHANNEL}" \
	  --description "Self-service trial channel"; fi

enterprise-portal:
	hack/setup-enterprise-portal

entitlements:
	@app_id=$$(hack/resolve-app-metadata | jq -r .app_id); \
	replicated api post "/v3/app/$$app_id/license-field" \
	  -b '{"name":"member_count_max","title":"Maximum Members","type":"Integer","default":"100"}' \
	  2>/dev/null || echo "Field member_count_max already exists"

webhook-subscription:
	hack/setup-webhook-subscription

verify-webhook:
	hack/test-webhook -u "${REPLICATED_SITE_URL}" -s "${REPLICATED_WEBHOOK_SECRET}"

verify-replicated: verify-webhook
	@hack/resolve-app-metadata > /dev/null && echo "Channel and app verified."

replicated-clean:
	@echo "Removing webhook subscription..." && \
	replicated api get /v3/notification_subscriptions 2>/dev/null | \
	  jq -r '.[] | select(.name == "Salesforce CRM Sync") | .id' | \
	  while read -r id; do replicated api delete "/v3/notification_subscription/$$id"; done
```

### `hack/setup-webhook-subscription`

Creates the event notification subscription via the undocumented (but functional) `POST /v3/notification_subscription` endpoint. Earns its place as a script for the same reason as `setup-enterprise-portal`: large JSON body with interpolated values and idempotency logic.

**API details** (discovered from `replicatedhq/vandoor` source — tagged `v3-draft` in swagger, not in the public spec, but uses the same auth layer as all other `replicated api` calls):

- `POST /v3/notification_subscription` — create
- `GET /v3/notification_subscriptions` — list (for idempotency check)
- `DELETE /v3/notification_subscription/:id` — delete (for cleanup)
- `POST /v3/notification_webhook/test` — test delivery

**Request body:**

```json
{
  "name": "Salesforce CRM Sync",
  "eventConfigs": [
    {"eventType": "customer.created", "filters": {}},
    {"eventType": "customer.updated", "filters": {}},
    {"eventType": "customer.license_expiring", "filters": {}},
    {"eventType": "customer.pending_self_service_signup", "filters": {}},
    {"eventType": "release.assets_downloaded", "filters": {}},
    {"eventType": "instance.created", "filters": {}},
    {"eventType": "instance.upgrade_completed", "filters": {}},
    {"eventType": "instance.inactive", "filters": {}}
  ],
  "isEnabled": true,
  "webhookUrl": "<REPLICATED_SITE_URL>",
  "webhookSecret": "<REPLICATED_WEBHOOK_SECRET>"
}
```

**Idempotency:** List existing subscriptions via `GET /v3/notification_subscriptions`, check if one named `Salesforce CRM Sync` already exists. If found, skip creation and print the existing subscription ID.

**Cleanup extension:** `make replicated-clean` should also delete the webhook subscription (list, find by name, `DELETE /v3/notification_subscription/:id`).

## Resolved Questions

**1. ~~Demo customer `custom_id`~~ — Removed.** No CLI-created demo customer needed. The self-service trial signup on the Enterprise Portal creates the Replicated customer and fires the webhook events that drive the Salesforce integration. Sales-led fulfillment is demonstrated via the existing `make import` data.

**2. Webhook event type strings — Confirmed.** The dot-notation strings (`customer.created`, `instance.created`, etc.) are the canonical keys, confirmed by the `NotificationEventConfig.EventType` field in `replicatedhq/vandoor:pkg/notifications/types/types.go` and the `SearchNotificationEventTypes` handler's `event.Key()` values.

**3. Webhook signing secret flow — Resolved by automation.** `.env` is the single source of truth. `make webhook-subscription` passes `REPLICATED_WEBHOOK_SECRET` to the subscription create API, and `make webhook-secret` deploys it to Salesforce CMDT. No manual copy-paste.

## Script Conventions

All new `hack/` scripts should use:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

The existing scripts (`hack/import`, `hack/clean`) omit `set -euo pipefail`. Adding it to new scripts prevents silent failures from empty API responses or jq parse errors. Retrofitting existing scripts is out of scope but noted as a follow-up.

## Dependencies & Risks

| Dependency | Status | Risk |
|---|---|---|
| Salesforce Site deployed and accessible | Tracked in issue #9 | Webhook verification will fail until Site is live |
| `REPLICATED_WEBHOOK_SECRET` matches between Replicated and Salesforce CMT | `make webhook-secret` exists | Mismatch causes HMAC verification failures — silent data loss |
| `replicated` CLI installed and authenticated | Prerequisite | Scripts fail with clear error if missing |
| Notification subscription API is undocumented (`v3-draft`) | Functional, used by Vendor Portal UI | Endpoint could change without notice; pin to known request shape from vandoor source |
| Webhook receiver deployed (issue #10) | Merged | Verify-webhook depends on the endpoint being live |

## Success Metrics

- `make setup-replicated` completes without errors on a fresh app
- `make verify-replicated` passes all checks
- Self-service signup URL is accessible and creates a trial customer
- Webhook events flow from Replicated to Salesforce (verified via `hack/test-webhook`)

## Sources & References

### Internal References

- User Story: `docs/User Story.md`
- Architecture: `docs/research/2026-03-16-event-driven-bidirectional-sync.md`
- Existing CLI pattern: `hack/import:48` — `replicated app ls --output json`
- Existing webhook test: `hack/test-webhook`
- Credential storage evaluation: `docs/solutions/security-issues/secret-storage-evaluation-for-cmt-credentials.md`
- CLI validation lesson: `docs/solutions/integration-issues/salesforce-webhook-endpoint-testing-integration.md`
- ID field confusion lesson: `docs/solutions/integration-issues/wrong-identifier-type-in-api-call.md`
- HMAC secret sync lesson: `docs/solutions/integration-issues/webhook-receiver-hmac-verification.md`
- "Every config needs CLI path": `docs/solutions/security-issues/webhook-receiver-code-review-findings.md`

### External References

- [Replicated Enterprise Portal Self-Service Signup](https://docs.replicated.com/vendor/enterprise-portal-self-serve-signup)
- [Replicated Event Notifications Webhooks](https://docs.replicated.com/vendor/event-notifications-webhooks)
- [Replicated Event Notifications Create](https://docs.replicated.com/vendor/event-notifications-create)
- [Replicated Customer Create CLI](https://docs.replicated.com/reference/replicated-cli-customer-create)
- [Replicated Channel CLI](https://docs.replicated.com/reference/replicated-cli-channel)
- [Replicated Vendor API v3 Spec](https://api.replicated.com/vendor/v3/spec/vendor-api-v3.json)
- [Manage Customer License Fields](https://docs.replicated.com/vendor/licenses-adding-custom-fields)

### Undocumented API References (from vandoor source)

- Route registration: `replicatedhq/vandoor:pkg/daemons/vendor_api/v3_write.go` — `POST /v3/notification_subscription`, `PUT /v3/notification_subscription/:id`, `DELETE /v3/notification_subscription/:id`
- Route registration: `replicatedhq/vandoor:pkg/daemons/vendor_api/v3_read.go` — `GET /v3/notification_subscriptions`, `GET /v3/notification_event_types`
- Create handler: `replicatedhq/vandoor:handlers/vendor-api/replv3/notifications/notification_subscription_create.go`
- Types: `replicatedhq/vandoor:pkg/notifications/types/types.go` — `NotificationEventConfig{EventType string, Filters map[string]interface{}}`
- Test webhook: `replicatedhq/vandoor:handlers/vendor-api/replv3/notifications/notification_webhook_test_send.go`

### Related Work

- Issue #6: Event-driven bidirectional sync (parent epic)
- Issue #10: Webhook receiver with HMAC verification (merged)
- Issue #11: Trial lifecycle event handlers (open)
- Issue #12: Instance and license event handlers (open)
- Issue #28: Named Credentials migration (open)
