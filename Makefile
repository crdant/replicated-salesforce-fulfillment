ORG_ALIAS ?= shortrib

deploy:
	sf project deploy start --manifest package.xml --post-destructive-changes create-license/main/default/destructiveChangesPost.xml -o "$(ORG_ALIAS)"

permissions:
	sf org assign permset --name Replicated_API_Access --target-org "$(ORG_ALIAS)"

retrieve:
	sf project retrieve start --manifest package.xml -o "$(ORG_ALIAS)"

credentials:
	hack/set-api-token -o "$(ORG_ALIAS)" -t "${REPLICATED_SERVICE_ACCOUNT_TOKEN}"

webhook-secret:
	hack/set-webhook-secret -o "$(ORG_ALIAS)" -s "${REPLICATED_WEBHOOK_SECRET}"

channels:
	hack/create-channel -a "$${REPLICATED_APP}" -n "$${REPLICATED_CHANNEL}"

enterprise-portal:
	hack/setup-enterprise-portal

entitlements:
	hack/create-license-field

webhook-subscription:
	hack/setup-webhook-subscription

verify-webhook:
	hack/test-webhook -u "${REPLICATED_SITE_URL}" -s "${REPLICATED_WEBHOOK_SECRET}"

verify-replicated:
	@hack/resolve-app-metadata

verify: verify-webhook verify-replicated

clean:
	hack/clean -o "$(ORG_ALIAS)"

replicated-clean:
	hack/clean-webhook-subscription

import:
	hack/import -o "$(ORG_ALIAS)" -d data
