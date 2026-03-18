public class CustomerCreatedHandler implements Queueable {
    private String payload;

    public CustomerCreatedHandler(String payload) {
        this.payload = payload;
    }

    public void execute(QueueableContext context) {
        Map<String, Object> webhookPayload = (Map<String, Object>) JSON.deserializeUntyped(this.payload);
        Map<String, Object> data = (Map<String, Object>) webhookPayload.get('data');

        String customerId = (String) data.get('customer_id');
        String customerName = (String) data.get('customer_name');
        String email = (String) data.get('email');
        String licenseType = (String) data.get('license_type');
        String expiresAt = (String) data.get('expires_at');
        String channelName = (String) data.get('channel_name');

        // Try to find an existing unconverted Lead by email
        Lead lead = null;
        if (String.isNotBlank(email)) {
            List<Lead> leads = [
                SELECT Id, Replicated_Customer_Id__c
                FROM Lead
                WHERE Email = :email AND IsConverted = false
                LIMIT 1
            ];
            if (!leads.isEmpty()) {
                lead = leads[0];
            }
        }

        if (lead != null) {
            // Enrich the existing Lead
            lead.Replicated_Customer_Id__c = customerId;
            lead.Replicated_License_Type__c = licenseType;
            lead.Replicated_Channel__c = channelName;
            if (String.isNotBlank(expiresAt)) {
                lead.Replicated_License_Expiry__c = Date.valueOf(expiresAt.substring(0, 10));
            }

            SyncGuard.inboundSyncIds.add(lead.Id);
            update lead;
        } else {
            // No matching Lead found -- create one with all available data
            System.debug('CustomerCreatedHandler: no matching Lead for email ' + email + ', creating new Lead');
            Lead newLead = new Lead(
                FirstName = '',
                LastName = String.isNotBlank(customerName) ? customerName : 'Unknown',
                Company = String.isNotBlank(customerName) ? customerName : 'Unknown',
                Email = email,
                LeadSource = 'Self-Service Trial',
                Status = 'New',
                Replicated_Customer_Id__c = customerId,
                Replicated_License_Type__c = licenseType,
                Replicated_Channel__c = channelName,
                Replicated_License_Expiry__c = String.isNotBlank(expiresAt) ? Date.valueOf(expiresAt.substring(0, 10)) : null
            );

            insert newLead;
            SyncGuard.inboundSyncIds.add(newLead.Id);
        }
    }
}
