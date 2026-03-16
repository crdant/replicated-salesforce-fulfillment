# Replicated Salesforce Fulfillment

Salesforce DX project that integrates the Replicated Platform with Salesforce for automated license fulfillment and bidirectional event sync.

## Project Structure

- `create-license/main/default/` — Salesforce source (classes, triggers, objects, layouts, profiles)
- `data/` — Sample data for import
- `hack/` — Utility scripts
- `docs/` — Research documents and user stories

## Development

### Prerequisites

- Salesforce CLI (`sf`)
- Access to Salesforce org: `shortriblabs-dev-ed.develop.my.salesforce.com`
- Replicated Vendor Portal API token

### Common Commands

```bash
make deploy      # Deploy to Salesforce org
make retrieve    # Retrieve latest metadata from org
make credentials # Set Replicated API token
make import      # Import sample data
make clean       # Clean up org data (use with caution)
```

### Salesforce API Version

All metadata uses API version **61.0**.

## Conventions

### Branch Naming

`{type}/{author}/{verb-phrase-description}`

- Types: `feature`, `chore`, `docs`, `fix`
- Author: `crdant` (Chuck), `claude` (Claude)
- Examples: `feature/claude/adds-sync-guard`, `chore/claude/prepares-claude-md`

### Apex Class Metadata

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>61.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

### Key Design Patterns

- **Queueable for callouts**: All Replicated API calls go through Queueable classes (e.g., `ReplicatedFulfillment`) because Salesforce triggers can't make HTTP callouts directly.
- **Platform Events for webhooks**: Inbound webhooks publish `Replicated_Webhook__e` Platform Events for async processing (decouples receipt from handling).
- **SyncGuard for loop prevention**: Static sets (`SyncGuard.inboundSyncIds`) prevent infinite loops in bidirectional sync.
- **`custom_id` as reconciliation key**: Replicated customer `custom_id` = Salesforce Account ID. This is the bidirectional join key.

### Key Salesforce Objects

- `Product2` — Custom fields map to Replicated app/channel/entitlements
- `Order.LicenseId__c` — Stores generated Replicated license ID
- `Replicated_Instance__c` — Tracks Replicated instances (read-only in SF)
- `Replicated_Webhook__e` — Platform Event for inbound webhook processing
- `ReplicatedVendorPortalCredential__mdt` — API token storage
- `Replicated_Webhook_Secret__mdt` — HMAC signing secret storage
