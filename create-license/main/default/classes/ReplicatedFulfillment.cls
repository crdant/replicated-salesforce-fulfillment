public without sharing class ReplicatedFulfillment implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;

    private ReplicatedPlatform platform;

    public ReplicatedFulfillment(OrderTerms terms) {
        this.terms = terms;
        Replicated_Vendor_Portal_API_Credential__mdt defaultCredential = [
            SELECT ApiToken__c
            FROM Replicated_Vendor_Portal_API_Credential__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        this.platform = new ReplicatedPlatform(defaultCredential);
    }

    private void setLicenseId(String licenseId) {
        Id orderId = this.terms.orderId();
        Order order = [SELECT Id, LicenseId__c FROM Order WHERE Id = :orderId LIMIT 1];
        order.LicenseId__c = licenseId;
        update order;
    }

    private void attachLicense(String appId, String customerId) {
        String license = this.platform.getLicenseFile(appId, customerId);
        if (license == null) {
            return;
        }

        Id orderId = this.terms.orderId();

        ContentVersion contentVersion = new ContentVersion();
        contentVersion.VersionData = Blob.valueOf(license);
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

    public void execute(QueueableContext context) {
        ReplicatedCustomer customer = this.platform.loadCustomer(this.terms);

        if (customer == null) {
            customer = this.platform.createLicense(this.terms);
        } else {
            customer.updateTerms(this.terms);
            this.platform.updateCustomer(customer);
        }

        String appId = this.terms.applicationId();
        this.setLicenseId(customer.licenseId);
        this.attachLicense(appId, customer.id);
        this.platform.inviteToPortal(appId, customer.id, this.terms.customerEmail());
    }
}
