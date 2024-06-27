public class ReplicatedLicense implements Queueable, Database.AllowsCallouts {
    private Contract contract;

    public ReplicatedLicense(Contract contract) {
        this.contract = contract;
    }

    public void execute(QueueableContext context) {
        ReplicatedVendorPortalCredential__mdt defaultCredential = [
            SELECT ApiToken__c 
            FROM ReplicatedVendorPortalCredential__mdt 
            WHERE DeveloperName = 'Default' 
            LIMIT 1
        ];

        ReplicatedPlatform platform = new ReplicatedPlatform(defaultCredential);
        platform.createLicense(this.contract);
    }
}