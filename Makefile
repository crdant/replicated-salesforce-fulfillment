deploy:
	sf project deploy start --manifest package.xml -o shortrib

retrieve:
	sf project retrieve start --manifest package.xml -o shortrib

credentials:
	echo "ReplicatedCredentialManager.setApiToken('${REPLICATED_SERVICE_ACCOUNT_TOKEN}');" | sf apex run --target-org "${ORG_ALIAS}"

webhook-secret:
	hack/set-webhook-secret -o shortrib -s "${REPLICATED_WEBHOOK_SECRET}"

channels:
	@id=$$(replicated channel ls --app "$${REPLICATED_APP}" --output json | \
	  jq -r --arg ch "$${REPLICATED_CHANNEL}" '.[] | select(.channelSlug == $$ch) | .id'); \
	if [ -n "$$id" ]; then echo "Channel '$${REPLICATED_CHANNEL}' exists ($$id)"; \
	else replicated channel create --app "$${REPLICATED_APP}" --name "$${REPLICATED_CHANNEL}" \
	  --description "Self-service trial channel"; fi

clean:
	hack/clean -o "${ORG_ALIAS}"

import:
	hack/import -o "${ORG_ALIAS}" -d data
