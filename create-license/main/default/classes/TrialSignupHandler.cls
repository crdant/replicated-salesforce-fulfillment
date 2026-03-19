// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Lead records.
public without sharing class TrialSignupHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public TrialSignupHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Parse all payloads and collect emails for bulk duplicate check.
        List<Map<String, Object>> dataList = new List<Map<String, Object>>();
        Set<String> emails = new Set<String>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> data;
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
                data = (Map<String, Object>) parsed.get('data');
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'TrialSignupHandler: malformed payload, skipping');
                continue;
            }

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'TrialSignupHandler: missing data in payload');
                continue;
            }

            String email = (String) data.get('email');
            if (String.isBlank(email)) {
                System.debug(LoggingLevel.WARN, 'TrialSignupHandler: blank email, skipping');
                continue;
            }

            dataList.add(data);
            emails.add(email);
        }

        // Single SOQL: find all existing unconverted Leads by email.
        Set<String> existingEmails = new Set<String>();
        for (Lead l : [SELECT Email FROM Lead WHERE Email IN :emails AND IsConverted = false]) {
            existingEmails.add(l.Email);
        }

        // Build insert list, skipping duplicates.
        List<Lead> toInsert = new List<Lead>();
        for (Map<String, Object> data : dataList) {
            String email = (String) data.get('email');
            if (existingEmails.contains(email)) {
                continue;
            }

            String customerName = (String) data.get('customer_name');
            toInsert.add(new Lead(
                LastName = String.isNotBlank(customerName) ? customerName : 'Unknown',
                Company = String.isNotBlank(customerName) ? customerName : 'Unknown',
                Email = email,
                LeadSource = 'Self-Service Trial',
                Status = 'New'
            ));

            // Track email so later events in the same batch don't duplicate.
            existingEmails.add(email);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Lead l : toInsert) {
                SyncGuard.inboundSyncIds.add(l.Id);
            }
        }
    }
}
