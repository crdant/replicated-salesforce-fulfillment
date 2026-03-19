# Replicated Fulfillment for Salesforce

This project implements a fulfillment process in Salesforce that integrates
with the [Replicated Platform](https://replicated.com). It automates the
process of creating licenses and inviting customers to the Replicated
Enterprise Portal when orders are activated. It streamlines the workflow for
sales teams and ensures a seamless experience for customers acquiring
Replicated-powered software.

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

The solution involves components in the vendor's Salesforce org and the
Replicated Vendor Portal. Here's a high-level overview:

1. Salesforce Org: Contains custom objects, fields, and Apex code to manage
   the sales process and trigger the fulfillment process.
2. Replicated Vendor Portal: Provides the API for license creation,
   management, and Enterprise Portal invitations.

## Fulfillment Process

The fulfillment process automates license management and customer onboarding:

1. Create an Opportunity in Salesforce.
2. Add Products to the Opportunity, specifying quantities and relevant
   details.
3. Move the opportunity to the "Negotiation/Review" stage to create Order and
   Contract objects. These are used by the fulfillment process.
4. Activate the contract to activate the order.
5. Upon Order activation, the ReplicatedFulfillment class is triggered, which:
   - Creates or updates a Replicated license on the Replicated platform
   - Records the license ID on the Salesforce Order
   - Sends an Enterprise Portal invitation to the customer

This process ensures that customers are onboarded to the Enterprise Portal
immediately after the order is activated, improving the overall customer
experience and reducing the time to value.

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

2. **Product2**: Represents your products and their configurations. There are
   some custom fields that map to Replicated entitlements.

3. **Opportunity**: Represents a sales opportunity that includes Replicated
   products.

4. **Order**: Represents the final order that will trigger the fulfillment
   process. Includes `LicenseId__c` field to store the generated license ID.

5. **Validation Rules**: Ensure data integrity and enforce business rules.

6. **Apex Classes**:
   - `ReplicatedCustomer`, `ReplicatedLicenseEntitlement`: Data models for
     Replicated entities.
   - `ReplicatedPlatform`: Handles API interactions with Replicated,
     including license management and Enterprise Portal invitations.
   - `ReplicatedFulfillment`: Manages the entire fulfillment process,
     including license creation and portal invitation.
   - `OrderTerms`: Extracts relevant information from the Order.

7. **Apex Triggers**:
   - `CloseWonOpportunity`: Updates Opportunity status when a Contract is
     activated.
   - `ActivateOrder`: Activates the Order when a Contract is activated.
   - `FulfillOrder`: Triggers the fulfillment process when an order is
     activated.

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
7. Test the integration by creating and closing an Opportunity, then activating the resulting Contract and Order.

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
- `make setup-replicated`: Configure all Replicated Platform resources in one step.
- `make verify`: Verify Replicated app metadata and webhook endpoint.
- `make clean`: Clean up data in your org (use with caution).
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
