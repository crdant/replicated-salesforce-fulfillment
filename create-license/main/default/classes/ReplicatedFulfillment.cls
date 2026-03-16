public class ReplicatedFulfillment implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;

    private ReplicatedPlatform platform;

    public ReplicatedFulfillment(OrderTerms terms) {
        this.terms = terms;
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
        update order;
    }

    public void execute(QueueableContext context) {
        ReplicatedCustomer customer = this.platform.loadCustomer(this.terms);

        if (customer == null) {
            customer = this.platform.createLicense(this.terms);
        } else {
            customer.updateTerms(this.terms);
            this.platform.updateCustomer(customer);
        }

        this.setLicenseId(customer.licenseId);
        this.platform.inviteToPortal(this.terms.applicationId(), customer.id, this.terms.customerEmail());
    }
}
