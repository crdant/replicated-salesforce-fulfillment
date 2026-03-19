public without sharing class ReplicatedFulfillment implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;

    private ReplicatedPlatform platform;

    public ReplicatedFulfillment(OrderTerms terms) {
        this.terms = terms;
        this.platform = new ReplicatedPlatform();
    }

    public void execute(QueueableContext context) {
        // Phase 1: All callouts — Salesforce prohibits callouts after DML.
        String replicatedCustomerId = this.terms.replicatedCustomerId();
        Boolean needsAccountUpdate = false;
        ReplicatedCustomer customer;

        if (String.isNotBlank(replicatedCustomerId)) {
            // Account already has a Replicated customer ID — load and update that customer
            customer = this.platform.loadCustomerById(replicatedCustomerId);
            if (customer != null) {
                customer.updateTerms(this.terms);
                this.platform.updateCustomer(customer);
            } else {
                // Stored ID is stale; fall through to create
                customer = this.platform.createLicense(this.terms);
                needsAccountUpdate = true;
            }
        } else {
            // No customer ID on Account — search by custom_id (Account ID)
            customer = this.platform.loadCustomer(this.terms);
            if (customer != null) {
                // Found by custom_id — update and backfill Account
                customer.updateTerms(this.terms);
                this.platform.updateCustomer(customer);
                needsAccountUpdate = true;
            } else {
                // No match anywhere — create new customer
                customer = this.platform.createLicense(this.terms);
                needsAccountUpdate = true;
            }
        }

        String appId = this.terms.applicationId();
        String customerEmail = this.terms.customerEmail();

        String licenseFile = this.platform.getLicenseFile(appId, customer.id);
        this.platform.inviteToPortal(appId, customer.id, customerEmail);

        // Phase 2: All DML — after every callout is complete.
        Id orderId = this.terms.orderId();

        Order order = [SELECT Id, LicenseId__c FROM Order WHERE Id = :orderId LIMIT 1];
        order.LicenseId__c = customer.licenseId;
        update order;

        if (needsAccountUpdate) {
            Id accountId = this.terms.accountId();
            SyncGuard.outboundSyncIds.add(accountId);
            Account account = [SELECT Id, Replicated_Customer_Id__c FROM Account WHERE Id = :accountId LIMIT 1];
            account.Replicated_Customer_Id__c = customer.id;
            update account;
        }

        if (licenseFile != null) {
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.VersionData = Blob.valueOf(licenseFile);
            contentVersion.Title = 'Software License';
            contentVersion.PathOnClient = 'license.yaml';
            insert contentVersion;

            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id].ContentDocumentId;

            ContentDocumentLink docLink = new ContentDocumentLink();
            docLink.ContentDocumentId = docId;
            docLink.LinkedEntityId = orderId;
            docLink.ShareType = 'V';
            docLink.Visibility = 'AllUsers';
            insert docLink;
        }
    }
}
