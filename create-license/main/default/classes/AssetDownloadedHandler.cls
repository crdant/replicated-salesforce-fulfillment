public class AssetDownloadedHandler implements Queueable {
    private String payload;

    public AssetDownloadedHandler(String payload) {
        this.payload = payload;
    }

    public void execute(QueueableContext context) {
        Map<String, Object> webhookPayload = (Map<String, Object>) JSON.deserializeUntyped(this.payload);
        Map<String, Object> data = (Map<String, Object>) webhookPayload.get('data');

        String customerId = (String) data.get('customer_id');
        String customerName = (String) data.get('customer_name');
        String email = (String) data.get('email');

        // Check if an Account already exists for this customer (idempotent)
        List<Account> existingAccounts = [
            SELECT Id FROM Account
            WHERE Replicated_Customer_Id__c = :customerId
            LIMIT 1
        ];
        if (!existingAccounts.isEmpty()) {
            System.debug('AssetDownloadedHandler: Account already exists for customer ' + customerId + ', skipping');
            return;
        }

        // Try to find an unconverted Lead by Replicated_Customer_Id__c
        List<Lead> leads = [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
                   Replicated_Channel__c, Replicated_License_Expiry__c
            FROM Lead
            WHERE Replicated_Customer_Id__c = :customerId AND IsConverted = false
            LIMIT 1
        ];

        if (!leads.isEmpty()) {
            convertLead(leads[0], customerId);
        } else {
            // No Lead found -- create Account + Contact + Opportunity directly
            System.debug('AssetDownloadedHandler: no Lead for customer ' + customerId + ', creating Account/Contact/Opportunity directly');
            createAccountContactOpportunity(customerId, customerName, email);
        }
    }

    private void convertLead(Lead lead, String customerId) {
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);

        LeadStatus convertedStatus = [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];
        lc.setConvertedStatus(convertedStatus.MasterLabel);
        lc.setDoNotCreateOpportunity(false);

        SyncGuard.inboundSyncIds.add(lead.Id);
        Database.LeadConvertResult result = Database.convertLead(lc);

        if (result.isSuccess()) {
            // Set Replicated_Customer_Id__c on the new Account
            Account acc = [SELECT Id, Replicated_Customer_Id__c FROM Account WHERE Id = :result.getAccountId()];
            acc.Replicated_Customer_Id__c = customerId;

            // Carry over additional fields from Lead if available
            if (String.isNotBlank(lead.Replicated_License_Type__c)) {
                acc.Replicated_License_Type__c = lead.Replicated_License_Type__c;
            }
            if (String.isNotBlank(lead.Replicated_Channel__c)) {
                acc.Replicated_Channel__c = lead.Replicated_Channel__c;
            }

            SyncGuard.inboundSyncIds.add(acc.Id);
            update acc;
        } else {
            System.debug(LoggingLevel.ERROR, 'AssetDownloadedHandler: Lead conversion failed for ' + lead.Id);
        }
    }

    private void createAccountContactOpportunity(String customerId, String customerName, String email) {
        String name = String.isNotBlank(customerName) ? customerName : 'Unknown';

        Account acc = new Account(
            Name = name,
            Replicated_Customer_Id__c = customerId
        );
        insert acc;
        SyncGuard.inboundSyncIds.add(acc.Id);

        Contact con = new Contact(
            LastName = name,
            Email = email,
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = name + ' - Trial Conversion',
            AccountId = acc.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }
}
