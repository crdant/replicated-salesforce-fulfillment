public class ReplicatedLicense implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;

    public ReplicatedLicense(OrderTerms terms) {
        this.terms = terms;
    }

    public void execute(QueueableContext context) {
        ReplicatedVendorPortalCredential__mdt defaultCredential = [
            SELECT ApiToken__c 
            FROM ReplicatedVendorPortalCredential__mdt 
            WHERE DeveloperName = 'Default' 
            LIMIT 1
        ];

        ReplicatedPlatform platform = new ReplicatedPlatform(defaultCredential);
        if ( !platform.customerExists(this.terms) ) {
            String licenseId = platform.createLicense(this.terms);

            Id orderId = this.terms.orderId();
            Order order = [SELECT Id, LicenseId__c FROM Order WHERE Id = :orderId LIMIT 1];
            order.LicenseId__c = licenseId;
            update order ;
            return;
        } else {
          System.debug('TO DO: Handle existing customer');
        }
        
    }
}