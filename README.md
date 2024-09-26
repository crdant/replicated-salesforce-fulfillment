# Replicated License Generation and Fulfillment for Salesforce

This project integrates Replicated license generation and fulfillment with
Salesforce, automating the process of creating licenses, generating
installation instructions, and delivering these to customers when orders are
activated. It provides a comprehensive solution that streamlines the workflow
for sales teams and ensures a seamless experience for customers acquiring
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
capabilities of the Replicated platform. The goal was to create a seamless
workflow that would allow sales teams to generate licenses and provide
customers with everything they need to get started, all automatically as part
of their normal process without requiring manual intervention or switching
between systems.

## Architecture

The solution involves components in the vendor's Salesforce org, the
Replicated Vendor Portal, and the customer's environment where the license
will be used. Here's a high-level overview:

1. Salesforce Org: Contains custom objects, fields, and Apex code to manage
   the sales process and trigger the fulfillment process.
2. Replicated Vendor Portal: Provides the API for license creation and
   management.
3. Customer Environment: Where the generated license and installation
   instructions will be used with Replicated-powered software.

## Enhanced Fulfillment Process

The fulfillment process has been significantly expanded to provide a more
complete solution:

1. Create an Opportunity in Salesforce.
2. Add Products to the Opportunity, specifying quantities and relevant
   details.
3. Mark the Opportunity as Closed Won.
4. A Contract and Order are automatically created based on the Closed Won
   Opportunity.
5. Activate the contract to activate the order.
6. Upon Order activation, the ReplicatedFulfillment class is triggered, which:
   - Generates or updates a Replicated license
   - Retrieves the license file from Replicated
   - Generates appropriate installation instructions based on the product
     configuration
   - Attaches the license file and installation instructions to the Order
   - Sends an email to the customer with the license file and installation
     instructions

This enhanced process ensures that customers receive everything they need to
start using the software immediately after the order is activated, improving
the overall customer experience and reducing the time to value.

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

These entitlements determine which installation instructions are generated and
included in the fulfillment email.

## Salesforce Objects and Their Roles

1. **ReplicatedVendorPortalCredential__mdt**: Stores API credentials for
   authenticating with the Replicated Vendor Portal.

2. **Product2**: Represents Replicated products and their configurations.

3. **Opportunity**: Represents a sales opportunity that includes Replicated products.

4. **Order**: Represents the final order that will trigger the fulfillment
   process. Includes `LicenseId__c` field to store the generated license ID.

5. **Validation Rules**: Ensure data integrity and enforce business rules.

6. **Apex Classes**:
   - `ReplicatedApplication`, `ReplicatedChannel`, `ReplicatedCustomer`,
     `ReplicatedLicenseEntitlement`: Data models for Replicated entities.
   - `ReplicatedPlatform`: Handles API interactions with Replicated.
   - `ReplicatedFulfillment`: Manages the entire fulfillment process,
     including license generation, file attachments, and email sending.
   - `OrderTerms`: Extracts relevant information from the Order.
   - `ReplicatedInstallInstructions`: Generates installation instructions
     based on product configuration.

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
5. Create a `ReplicatedVendorPortalCredential__mdt` record with your API token.
6. Assign appropriate permissions to users.
7. Test the integration by creating and closing an Opportunity, then activating the resulting Contract and Order.

## Usage

The provided Makefile includes several useful commands:

- `make deploy`: Deploy the project to your Salesforce org.
- `make retrieve`: Retrieve the latest metadata from your Salesforce org.
- `make credentials`: Set the Replicated API token in your org.
- `make clean`: Clean up data in your org (use with caution).
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
