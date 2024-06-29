# Replicated License Generation for Salesforce

This project integrates Replicated license generation with Salesforce,
automating the process of creating licenses when opportunities are closed and
orders are activated. It streamlines the workflow for sales teams and ensures
seamless license creation for Replicated products.

[![Integrating the Replicated Platform into Your Sales Process](https://cdn.loom.com/sessions/thumbnails/a07b98c049e24132933a410edeaa55b3-with-play.gif)](https://www.loom.com/share/a07b98c049e24132933a410edeaa55b3)

## Background

Integrating license management into their sales process is a common
requirement for software vendors using the Replicated Platform. While
Replicated focuses on distribution and installation, many vendors will want to
streamline their sales process and automate license generation directly from
their CRM.

This project arose from discussions with Replicated customers about how to
bridge the gap between their sales processes and the license management
capabilities of the Replicated platform. The goal was to create a seamless
workflow that would allow sales teams to generate licenses automatically as
part of their normal without requiring manual intervention or switching
between systems.

## Architecture

The solution involves components in the vendor's Salesforce org, the
Replicated Vendor Portal, and the customer's environment where the license
will be used. Here's a high-level overview:

1. Salesforce Org: Contains custom objects, fields, and Apex code to manage
   the sales process and trigger license generation.
2. Replicated Vendor Portal: Provides the API for license creation and
   management.
3. Customer Environment: Where the generated license will be used with
   Replicated-powered software.

## Workflow

1. Create an Opportunity in Salesforce.

2. Add Products to the Opportunity, specifying quantities and relevant
   details.

3. Mark the Opportunity as Closed Won.

4. An Contract and Order are automatically created based on the Closed Won Opportunity.

5. Activated the contract in order to activate the order.

6. Upon Order activation, a Replicated license is automatically generated and
   associated with the Order.

## Product Setup

Products in Salesforce are configured to represent Replicated applications and
their associated entitlements:

1. **Application and Release Channel**: 
   - `Application__c`: Specifies the Replicated application.
   - `ReleaseChannel__c`: Defines the release channel (e.g., Stable, Beta).

2. **Replicated Entitlements**:
   - `IsAdminConsoleEnabled__c`: Enables/disables the Admin Console feature.
     Maps to the "KOTS Install Enabled" license option.
   - `IsAirgapEnabled__c`: Indicates if airgap installations are supported.
     Maps to the "Airgap Download Enabled" license option.
   - `IsEmbeddedClusterEnabled__c`: Enables/disables the embedded cluster feature.
     Maps to the "Embedded Cluster Enabled" license option.
   - `IsAddOn__c`: Identifies the product as an add-on.

Ensure these fields are properly set when configuring products to reflect the
correct Replicated application, release channel, and entitlements.

## Salesforce Objects and Their Roles

1. **Replicated_Vendor_Portal_API_Credential__mdt**: Stores API credentials
   for authenticating with the Replicated Vendor Portal. Used by Apex classes
   to make secure API calls to generate licenses.

2. **Product2 (Standard object with custom fields)**: Represents Replicated
   products and their configurations. Custom fields define application,
   release channel, and entitlements.

3. **Opportunity (Standard object)**: Represents a sales opportunity that
   includes Replicated products. When closed as won, triggers the order
   creation process.

4. **Order (Standard object with custom fields)**: Represents the final order
   that will generate a Replicated license. `LicenseId__c`: Stores the ID of
   the generated Replicated license.

5. **Validation Rules**: Ensure data integrity and enforce business rules.
   Examples: `ValidateIsAirgapEnabled`, `ValidateSingleCoreProduct`.

6. **Apex Classes**: Contain the business logic for license generation and
   integration with Replicated. Handle API calls, data processing, and license
   creation workflows.

7. **Apex Triggers**:
   * `CloseWonOpportunity`: Initiates the order creation process when an opportunity is closed as won.
   * `ActivateOrder`: Triggers the license generation process when an order is activated.
   * `CreateLicense`: Handles the actual creation of the Replicated license.

This structure ensures a seamless flow from opportunity creation to license
generation, with proper data validation and business rule enforcement at each
step.

## Setup and Configuration

### Prerequisites

1. Salesforce CLI (`sf`) installed on your local machine.
   - Download from [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli)
   - Follow the installation instructions for your operating system

2. Access to a Salesforce org with system administrator privileges

3. Replicated Vendor Portal account with API access

### Steps

1. Clone this repository to your local machine:

```
git clone https://github.com/your-username/replicated-salesforce-integration.git
cd replicated-salesforce-integration
```

2. Log in to your Salesforce org using the Salesforce CLI:

```
sf org login web -a YourOrgAlias
```

This will open a web browser for you to log in to your Salesforce org. Once
logged in, you can close the browser window.

3. Deploy the code to your Salesforce org:

```
sf force:source:deploy -p force-app
```

4. Set up your products in Salesforce:
- Navigate to the Product object in Salesforce Setup
- Create new products or modify existing ones to include the custom fields for
  Replicated applications (`Application__c`, `ReleaseChannel__c`, etc.)
- Ensure all relevant fields are populated for each product

5. Create a `Replicated_Vendor_Portal_API_Credential__mdt` record:
- In Salesforce Setup, go to Custom Metadata Types
- Click on "Manage Records" next to `Replicated_Vendor_Portal_API_Credential__mdt`
- Create a new record with the following details:
  - Label: Your chosen label (e.g., "Production API Credential")
  - API Token: Your Replicated Vendor Portal API token
  - [Add any other required fields for your implementation]

6. Assign appropriate permissions:
- Create or modify permission sets to grant access to the custom objects and fields
- Assign these permission sets to the relevant users

7. Test the integration:
- Create a new Opportunity
- Add Products to the Opportunity
- Close the Opportunity as Won
- Verify that an Order is created and a Replicated license is generated

### Troubleshooting

- If you encounter any deployment errors, check the Salesforce CLI output for
  specific error messages
- Verify that all custom fields and objects are correctly created in your
  Salesforce org
- Ensure that the API credentials are correctly set up and that your
  Replicated Vendor Portal account has the necessary permissions

For any additional issues or questions, please open an issue in this GitHub repository.

## Disclaimer

This code is provided as an example and is not officially supported by
Replicated. It is intended to serve as a starting point for integrating
Replicated license generation with Salesforce. Users should thoroughly test
and adapt this code to their specific needs before using it in a production
environment.

## License

This project is licensed under the Apache License, Version 2.0. See the
[LICENSE](./LICENSE) file for details.
