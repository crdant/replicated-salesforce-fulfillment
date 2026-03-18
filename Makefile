deploy:
	sf project deploy start --manifest package.xml -o shortrib

retrieve:
	sf project retrieve start --manifest package.xml -o shortrib

credentials:
	echo "ReplicatedCredentialManager.setApiToken('${REPLICATED_SERVICE_ACCOUNT_TOKEN}');" | sf apex run --target-org "${ORG_ALIAS}"

webhook-secret:
	hack/set-webhook-secret -o "${ORG_ALIAS}" -s "${REPLICATED_WEBHOOK_SECRET}"

clean:
	hack/clean -o "${ORG_ALIAS}"

import:
	hack/import -o "${ORG_ALIAS}" -d data
