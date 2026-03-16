public class ReplicatedFulfillment implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;

    private ReplicatedPlatform platform;
    private ReplicatedCustomer customer;

    public ReplicatedFulfillment(OrderTerms terms) {
        this.terms = terms;
        this.customer = new ReplicatedCustomer(terms);
        ReplicatedVendorPortalCredential__mdt defaultCredential = [
            SELECT ApiToken__c
            FROM ReplicatedVendorPortalCredential__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        this.platform = new ReplicatedPlatform(defaultCredential);
    }

    private void setLicenseId(String licenseId) {
        Id orderId = this.terms.orderId();
        Order order = [SELECT Id, LicenseId__c FROM Order WHERE Id = :orderId LIMIT 1];
        order.LicenseId__c = licenseId;
        update order ;
    }

    public void execute(QueueableContext context) {
        String licenseId = null;
        ReplicatedCustomer customer;

        if (!this.platform.customerExists(this.terms)) {
            licenseId = this.platform.createLicense(this.terms);
        } else {
            customer = this.platform.loadCustomer(this.terms);
            licenseId = customer.licenseId;
            customer.updateTerms(this.terms);
            this.platform.updateCustomer(customer);
        }

        this.setLicenseId(licenseId);
        this.platform.inviteToPortal(this.terms.applicationId(), licenseId, this.terms.customerEmail());
    }
}
