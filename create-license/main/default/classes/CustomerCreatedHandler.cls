// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Lead records.
public without sharing class CustomerCreatedHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public CustomerCreatedHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Parse all payloads and collect emails for bulk Lead lookup.
        List<Map<String, Object>> dataList = new List<Map<String, Object>>();
        Set<String> emails = new Set<String>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> data;
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
                data = (Map<String, Object>) parsed.get('data');
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'CustomerCreatedHandler: malformed payload, skipping');
                continue;
            }

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'CustomerCreatedHandler: missing data in payload');
                continue;
            }

            dataList.add(data);
            String email = (String) data.get('email');
            if (String.isNotBlank(email)) {
                emails.add(email);
            }
        }

        // Single SOQL: find all existing unconverted Leads by email.
        Map<String, Lead> leadsByEmail = new Map<String, Lead>();
        for (Lead l : [
            SELECT Id, Email, Replicated_Customer_Id__c
            FROM Lead
            WHERE Email IN :emails AND IsConverted = false
        ]) {
            leadsByEmail.put(l.Email, l);
        }

        List<Lead> toUpdate = new List<Lead>();
        List<Lead> toInsert = new List<Lead>();

        for (Map<String, Object> data : dataList) {
            String customerId = (String) data.get('customer_id');
            String customerName = (String) data.get('customer_name');
            String email = (String) data.get('email');
            String licenseType = (String) data.get('license_type');
            String expiresAt = (String) data.get('expires_at');
            String channelName = (String) data.get('channel_name');

            Lead lead = String.isNotBlank(email) ? leadsByEmail.get(email) : null;

            if (lead != null) {
                // Enrich the existing Lead.
                lead.Replicated_Customer_Id__c = customerId;
                lead.Replicated_License_Type__c = licenseType;
                lead.Replicated_Channel__c = channelName;
                lead.Replicated_License_Expiry__c = parseDate(expiresAt);

                SyncGuard.inboundSyncIds.add(lead.Id);
                toUpdate.add(lead);
            } else {
                // No matching Lead found -- create one with all available data.
                toInsert.add(new Lead(
                    LastName = String.isNotBlank(customerName) ? customerName : 'Unknown',
                    Company = String.isNotBlank(customerName) ? customerName : 'Unknown',
                    Email = email,
                    LeadSource = 'Self-Service Trial',
                    Status = 'New',
                    Replicated_Customer_Id__c = customerId,
                    Replicated_License_Type__c = licenseType,
                    Replicated_Channel__c = channelName,
                    Replicated_License_Expiry__c = parseDate(expiresAt)
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Lead l : toInsert) {
                SyncGuard.inboundSyncIds.add(l.Id);
            }
        }
    }

    private static Date parseDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            if (dateString.contains('T')) {
                dateString = dateString.substringBefore('T');
            }
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'CustomerCreatedHandler: failed to parse date: ' + dateString);
            return null;
        }
    }
}
