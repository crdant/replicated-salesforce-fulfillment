# Replicated Fulfillment for Salesforce

This project implements a bidirectional integration between Salesforce and the
[Replicated Platform](https://replicated.com). Outbound, it automates license
creation and Enterprise Portal onboarding when orders are activated. Inbound, it
syncs Replicated webhook events — trial signups, customer lifecycle changes,
instance telemetry, and asset downloads — back into Salesforce as Leads,
Accounts, Opportunities, and custom objects. The result is a closed-loop system
where sales teams work entirely inside Salesforce while the Replicated Platform
handles distribution and installation.

<!-- TO DO: Replace with Replicon video -->
[![Integrating the Replicated Platform into Your Sales Process](https://cdn.loom.com/sessions/thumbnails/a07b98c049e24132933a410edeaa55b3-with-play.gif)](https://www.loom.com/share/a07b98c049e24132933a410edeaa55b3)

## Background

Integrating license management and fulfillment into their sales process is a
common requirement for software vendors using the Replicated Platform. While
Replicated focuses on distribution and installation, many vendors want to
streamline their sales process and automate the entire fulfillment process
directly from their CRM.

This project arose from discussions with Replicated customers about how to
bridge the gap between their sales processes and the license management
capabilities of the Replicated platform. The goal was to create a workflow
that would allow sales teams to generate licenses and onboard customers
through the Enterprise Portal. All of this would be implemented as part of
their normal process without requiring manual intervention or switching
between systems.

## Architecture

The integration has two data paths that share a single reconciliation key:
the Replicated customer `custom_id` is set to the Salesforce Account ID.

**Outbound (Salesforce → Replicated)**

Salesforce triggers fire on record changes and enqueue `Queueable` classes
that call the Replicated Vendor Portal API through the `Replicated_API`
Named Credential. The Named Credential references the
`Replicated_Vendor_Portal` External Credential, so Apex never handles the
API token directly.

**Inbound (Replicated → Salesforce)**

Replicated sends webhook notifications to a public REST endpoint exposed via
a Salesforce Site. The `ReplicatedWebhookReceiver` verifies the HMAC-SHA256
signature, parses the payload, and publishes a `Replicated_Webhook__e`
Platform Event. The `ReplicatedWebhookSubscriber` trigger dispatches events
to handler-specific `Queueable` classes based on event type.

**Loop Prevention**

`SyncGuard` maintains static sets of record IDs currently being processed by
inbound or outbound paths. Triggers check these sets and skip records that
are already in-flight, preventing infinite sync loops in bidirectional
updates.

## Fulfillment Process

The outbound fulfillment process automates license management and customer
onboarding:

1. Create an Opportunity in Salesforce and add Products specifying quantities
   and relevant details.
2. Move the Opportunity to the "Negotiation/Review" stage. The
   `CreateOrderAndContract` trigger auto-creates a Contract, Order, and
   OrderItems from the Opportunity and its line items.
3. Activate the Contract. The `CloseWonOpportunity` trigger sets the
   Opportunity to "Closed Won" and the `ActivateOrder` trigger activates the
   Order.
4. Upon Order activation, the `FulfillOrder` trigger enqueues
   `ReplicatedFulfillment`, which:
   - Creates or updates a Replicated customer on the Replicated Platform
   - Records the Replicated customer ID on the Salesforce Account
   - Records the license ID on the Salesforce Order
   - Attaches the license file to the Order
   - Sends an Enterprise Portal invitation to the customer

`ReplicatedFulfillment` separates its work into a callout phase (all HTTP
requests first) and a DML phase (all database writes after), because
Salesforce prohibits callouts after DML in the same transaction.

## Webhook Event Sync

The inbound pipeline handles nine event types grouped into three categories.

### Customer Events

| Event | Handler | Action |
|-------|---------|--------|
| `customer.pending_signup` | `TrialSignupHandler` | Creates a Lead from a self-service trial signup. Deduplicates by email against existing unconverted Leads. |
| `customer.created` | `CustomerCreatedHandler` | Enriches an existing Lead with license metadata (customer ID, license type, channel, expiry). Skips trial-type licenses to avoid duplicating `TrialSignupHandler` work. Creates a new Lead if none is found. |
| `customer.updated` | `CustomerUpdatedHandler` | Syncs profile changes (name, license type, channel, expiry) to the matching Account. Only updates fields that actually changed. |
| `customer.ep_user_joined` | `EpUserJoinedHandler` | Converts the Lead to an Account, Contact, and Opportunity when the first user joins the Enterprise Portal. Falls back to direct record creation if no Lead exists. |
| `customer.license_expiring` | `LicenseExpiringHandler` | Creates a high-priority Task on the Account owner's queue to follow up on an expiring license. |

### Instance Events

| Event | Handler | Action |
|-------|---------|--------|
| `instance.created` | `InstanceEventHandler` | Upserts a `Replicated_Instance__c` record with status, app version, cloud provider, Kubernetes distribution, and check-in timestamps. |
| `instance.upgrade_completed` | `InstanceEventHandler` | Updates the instance's app version and last check-in time. |
| `instance.inactive` | `InstanceEventHandler` | Marks the instance status as "Unavailable". |

### Release Events

| Event | Handler | Action |
|-------|---------|--------|
| `release.asset_downloaded` | `AssetDownloadedHandler` | Creates a `Replicated_Download__c` record. For paid license downloads, stamps `FulfilledAt__c` on the oldest unfulfilled Order for the same Account and application. |

### Event Flow

1. Replicated POSTs a JSON payload to the Salesforce Site endpoint.
2. `ReplicatedWebhookReceiver` verifies the `X-Replicated-Signature` header
   using HMAC-SHA256 with the secret stored in
   `Replicated_Webhook_Secret__mdt`.
3. The receiver publishes a `Replicated_Webhook__e` Platform Event.
4. The `ReplicatedWebhookSubscriber` trigger batches events by type and
   enqueues one `Queueable` handler per event type.
5. Each handler performs bulk SOQL lookups and DML to process its events.

## Trial-to-Customer Lifecycle

The integration tracks the full progression from anonymous trial to paying
customer:

1. **Trial signup** — `customer.pending_signup` creates a Lead with source
   "Self-Service Trial".
2. **Customer created** — `customer.created` enriches the Lead with the
   Replicated customer ID, license type, channel, and expiry date.
3. **Portal join** — `customer.ep_user_joined` converts the Lead to an
   Account, Contact, and Opportunity (at "Qualification" stage).
4. **Sales progression** — The sales team advances the Opportunity through
   stages. At "Negotiation/Review", the Contract and Order are auto-created.
5. **Contract activation** — Activating the Contract closes the Opportunity
   as "Won" and activates the Order.
6. **Fulfillment** — Order activation triggers license creation (or update)
   and an Enterprise Portal invitation.
7. **Fulfillment confirmation** — `release.asset_downloaded` stamps
   `FulfilledAt__c` on the Order when the customer downloads paid software.

## Product Setup

Products in Salesforce are configured to represent Replicated applications and
their associated entitlements:

1. **Application and Release Channel**:
   - `Application__c`: Specifies the Replicated application.
   - `ReleaseChannel__c`: Defines the release channel.

2. **Replicated Entitlements**:
   - `IsAdminConsoleEnabled__c`: Enables/disables the Admin Console feature.
   - `IsAirgapEnabled__c`: Indicates if airgap installations are supported.
   - `IsEmbeddedClusterEnabled__c`: Enables/disables the embedded cluster
     feature.
   - `IsAddOn__c`: Identifies the product as an add-on.
   - `IsSnapshotSupported__c`: Indicates if snapshots are supported.
   - `IsSupportBundleUploadEnabled__c`: Enables/disables support bundle
     upload.

These entitlements are applied to the Replicated license created during
fulfillment.

## Salesforce Objects and Their Roles

1. **Replicated_API Named Credential**: Stores the endpoint URL and references the
   `Replicated_Vendor_Portal` External Credential for encrypted API token storage
   and automatic header injection on outbound callouts.

2. **Product2**: Represents your products and their configurations. Custom fields
   map to Replicated application, channel, and entitlement settings.

3. **Opportunity**: Represents a sales opportunity that includes Replicated
   products.

4. **Order**: Represents the final order that triggers the fulfillment process.
   - `LicenseId__c` — stores the generated Replicated license ID.
   - `FulfilledAt__c` — timestamp of first paid software download confirming
     order fulfillment.

5. **Lead**: Captures trial signups and pre-conversion customer data.
   - `Replicated_Customer_Id__c` — Replicated customer ID.
   - `Replicated_License_Type__c` — license type (trial, paid, etc.).
   - `Replicated_Channel__c` — release channel name.
   - `Replicated_License_Expiry__c` — license expiry date.

6. **Account**: Represents a converted customer.
   - `Replicated_Customer_Id__c` — Replicated customer ID (the bidirectional
     join key, matching the Replicated customer `custom_id`).
   - `Replicated_License_Type__c` — license type.
   - `Replicated_Channel__c` — release channel name.
   - `Replicated_License_Expiry__c` — license expiry date.

7. **Replicated_Download__c**: Tracks asset downloads from the Replicated
   Platform (read-only in Salesforce, linked to Account via `Account__c`).

8. **Replicated_Instance__c**: Tracks deployment instances with status,
   version, cloud provider, Kubernetes distribution, and check-in timestamps
   (read-only in Salesforce, linked to Account via `Account__c`).

9. **Replicated_Webhook__e**: Platform Event that decouples webhook receipt
   from handler processing.

10. **Replicated_Webhook_Secret__mdt**: Custom Metadata storing the HMAC
    signing secret for webhook signature verification.

11. **Validation Rules**: Ensure data integrity and enforce business rules.

12. **Apex Classes**:
    - `ReplicatedCustomer`, `ReplicatedLicenseEntitlement`: Data models for
      Replicated entities.
    - `ReplicatedPlatform`: Handles API interactions with Replicated,
      including license management and Enterprise Portal invitations.
    - `ReplicatedFulfillment`: Queueable that manages the outbound
      fulfillment process — license creation, file attachment, and portal
      invitation.
    - `OrderTerms`: Extracts license terms from an Order.
    - `ReplicatedWebhookReceiver`: REST endpoint that verifies webhook
      signatures and publishes Platform Events.
    - `ReplicatedEventType`: Constants for the nine supported webhook event
      types.
    - `WebhookPayloadUtils`: Parses customer IDs and dates from webhook
      payloads.
    - `SyncGuard`: Static ID sets for bidirectional loop prevention.
    - `TrialSignupHandler`: Creates Leads from trial signups.
    - `CustomerCreatedHandler`: Enriches Leads with license metadata.
    - `CustomerUpdatedHandler`: Syncs profile changes to Accounts.
    - `EpUserJoinedHandler`: Converts Leads to Account/Contact/Opportunity.
    - `AssetDownloadedHandler`: Tracks downloads and confirms order
      fulfillment.
    - `InstanceEventHandler`: Upserts instance telemetry records.
    - `LicenseExpiringHandler`: Creates Tasks for expiring licenses.

13. **Apex Triggers**:
    - `CreateOrderAndContract`: Auto-creates Contract, Order, and OrderItems
      when an Opportunity reaches "Negotiation/Review".
    - `CloseWonOpportunity`: Sets Opportunity to "Closed Won" when its
      Contract is activated.
    - `ActivateOrder`: Activates the Order when its Contract is activated.
    - `FulfillOrder`: Enqueues `ReplicatedFulfillment` when an Order is
      activated.
    - `ReplicatedWebhookSubscriber`: Dispatches Platform Events to
      handler-specific Queueable classes.

## Setup and Configuration

### Prerequisites

1. Salesforce CLI (`sf`) installed on your local machine.
2. Access to a Salesforce org with system administrator privileges.
3. Replicated Vendor Portal account with API access.

### Steps

1. Clone this repository to your local machine.
2. Log in to your Salesforce org using the Salesforce CLI.
3. Deploy the code to your Salesforce org using the provided Makefile:
   ```
   make deploy
   ```
4. Set up your products in Salesforce with the required custom fields.
5. Assign the API access permission set to your user:
   ```
   make permissions
   ```
6. Set the Replicated API token on the Named Credential:
   ```
   make credentials
   ```
   This requires the `REPLICATED_SERVICE_ACCOUNT_TOKEN` environment variable to be set.
   Note: The credential must be set immediately after deploy — any Order activation
   before this step will fail.
7. Set the webhook signing secret:
   ```
   make webhook-secret
   ```
   This requires the `REPLICATED_WEBHOOK_SECRET` environment variable to be set.
8. Test the integration by creating and closing an Opportunity, then activating the resulting Contract and Order.

## Replicated Platform Setup

Configure the Replicated Vendor Portal integration (channels, enterprise
portal, entitlements, and webhook subscription) after deploying the Salesforce
metadata and setting up your Salesforce Site.

### Prerequisites

1. [Replicated CLI](https://docs.replicated.com/reference/replicated-cli-installing) (`replicated`) installed and authenticated.
2. Salesforce metadata deployed (`make deploy`) and credentials configured (`make credentials`).
3. Salesforce Site created and activated (see [Salesforce Site Setup](#salesforce-site-setup) below).

### Steps

1. Copy `.env.example` to `.env` and fill in your values:
   ```
   cp .env.example .env
   ```
   `REPLICATED_SITE_URL` requires the Salesforce Site to be deployed and
   activated first -- use the webhook URL from that step.

2. Source your `.env` (or use [direnv](https://direnv.net/)) and run the
   orchestrator target:
   ```
   make setup-replicated
   ```
   This runs `channels`, `enterprise-portal`, `entitlements`, and
   `webhook-subscription` in sequence.

3. Verify the configuration:
   ```
   make verify
   ```
   This confirms the Replicated app metadata resolves correctly and the
   webhook endpoint responds to a test payload.

4. To tear down Replicated webhook resources:
   ```
   make replicated-clean
   ```

## Salesforce Site Setup

A Salesforce Site is required to expose the webhook endpoint publicly so
Replicated can POST event notifications to Salesforce. HMAC-SHA256 signature
verification in the Apex code handles security.

### Steps

1. Navigate to **Setup → Sites** and create a new Site.
2. Set the Site URL suffix (e.g., `replicated-webhooks`).
3. Grant the Site Guest User profile access to:
   - `ReplicatedWebhookReceiver` Apex class
   - Publish access on `Replicated_Webhook__e` Platform Event
4. Activate the Site.

The resulting webhook URL will be:

```
https://<org-domain>.my.salesforce-sites.com/services/apexrest/replicated/webhook
```

Configure this URL in the Replicated Vendor Portal under **Notifications →
Create Notification**:

1. Select the relevant event types (e.g., customer.created, instance.created,
   license expiring).
2. Set the webhook URL to the Salesforce Site URL above.
3. Configure the HMAC signing secret (must match the value stored in the
   `Replicated_Webhook_Secret__mdt` custom metadata record in Salesforce).
4. Optionally add custom headers for additional authentication.

## Usage

The provided Makefile includes several useful commands:

- `make deploy`: Deploy the project to your Salesforce org.
- `make retrieve`: Retrieve the latest metadata from your Salesforce org.
- `make credentials`: Set the Replicated API token in your org.
- `make webhook-secret`: Set the webhook HMAC signing secret in your org.
- `make setup-replicated`: Configure all Replicated Platform resources in one step.
- `make verify`: Verify Replicated app metadata and webhook endpoint.
- `make clean`: Clean up all data in your org, including Leads (use with caution).
- `make replicated-clean`: Remove Replicated webhook subscription.
- `make import`: Import sample data into your org.

## Troubleshooting

- Check Salesforce CLI output for specific error messages.
- Verify that all custom fields and objects are correctly created in your Salesforce org.
- Ensure that the API credentials are correctly set up and that your Replicated Vendor Portal account has the necessary permissions.

For any additional issues or questions, please open an issue in this GitHub repository.

## Disclaimer

This code is provided as an example and is not officially supported by Replicated. It is intended to serve as a starting point for integrating Replicated license generation with Salesforce. Users should thoroughly test and adapt this code to their specific needs before using it in a production environment.

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](./LICENSE) file for details.
