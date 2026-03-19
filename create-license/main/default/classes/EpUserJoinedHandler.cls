// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Account, Lead, Contact, and Opportunity records.
public without sharing class EpUserJoinedHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public EpUserJoinedHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Parse payloads, collect customer IDs. Filter to first-user events only.
        List<Map<String, Object>> dataList = new List<Map<String, Object>>();
        Set<String> customerIds = new Set<String>();
        Set<String> joinedEmails = new Set<String>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> data;
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
                data = (Map<String, Object>) parsed.get('data');
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: malformed payload, skipping');
                continue;
            }

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: missing data in payload');
                continue;
            }

            // Only process first-user events. Use instanceof to guard against
            // non-boolean payload values — a bad cast here would kill the batch.
            Object isFirstUser = data.get('is_first_user');
            if (!(isFirstUser instanceof Boolean) || !(Boolean) isFirstUser) {
                continue;
            }

            String customerId = (String) data.get('customer_id');
            if (String.isBlank(customerId)) {
                System.debug(LoggingLevel.WARN, 'EpUserJoinedHandler: blank customer_id, skipping');
                continue;
            }

            dataList.add(data);
            customerIds.add(customerId);
            String joinedEmail = (String) data.get('joined_email');
            if (String.isNotBlank(joinedEmail)) {
                joinedEmails.add(joinedEmail);
            }
        }

        if (dataList.isEmpty()) {
            return;
        }

        // Idempotency: bulk query existing Accounts by customer ID.
        Set<String> existingAccountCustomerIds = new Set<String>();
        for (Account acc : [
            SELECT Replicated_Customer_Id__c FROM Account
            WHERE Replicated_Customer_Id__c IN :customerIds
        ]) {
            existingAccountCustomerIds.add(acc.Replicated_Customer_Id__c);
        }

        // Bulk query unconverted Leads by customer ID.
        Map<String, Lead> leadsByCustomerId = new Map<String, Lead>();
        for (Lead l : [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
                   Replicated_Channel__c, Replicated_License_Expiry__c
            FROM Lead
            WHERE Replicated_Customer_Id__c IN :customerIds AND IsConverted = false
        ]) {
            leadsByCustomerId.put(l.Replicated_Customer_Id__c, l);
        }

        // Fallback: bulk query unconverted Leads by email for those not found by customer ID.
        Map<String, Lead> leadsByEmail = new Map<String, Lead>();
        if (!joinedEmails.isEmpty()) {
            for (Lead l : [
                SELECT Id, Email, Replicated_Customer_Id__c, Replicated_License_Type__c,
                       Replicated_Channel__c, Replicated_License_Expiry__c
                FROM Lead
                WHERE Email IN :joinedEmails AND IsConverted = false
            ]) {
                leadsByEmail.put(l.Email, l);
            }
        }

        // Cache the converted status label.
        LeadStatus convertedStatus = [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        // Process each event: convert Lead or create records directly.
        List<Database.LeadConvert> conversions = new List<Database.LeadConvert>();
        List<Lead> conversionLeads = new List<Lead>();
        List<String> conversionCustomerIds = new List<String>();
        List<Map<String, Object>> directCreates = new List<Map<String, Object>>();

        for (Map<String, Object> data : dataList) {
            String customerId = (String) data.get('customer_id');
            String joinedEmail = (String) data.get('joined_email');

            // Idempotent: skip if Account already exists.
            if (existingAccountCustomerIds.contains(customerId)) {
                continue;
            }

            // Look up Lead by customer ID first, then fall back to email.
            // Email fallback only matches Leads with no customer ID set — prevents
            // converting a Lead that belongs to a different Replicated customer.
            Lead lead = leadsByCustomerId.get(customerId);
            if (lead == null && String.isNotBlank(joinedEmail)) {
                Lead emailLead = leadsByEmail.get(joinedEmail);
                if (emailLead != null && String.isBlank(emailLead.Replicated_Customer_Id__c)) {
                    lead = emailLead;
                }
            }

            if (lead != null) {
                Database.LeadConvert lc = new Database.LeadConvert();
                lc.setLeadId(lead.Id);
                lc.setConvertedStatus(convertedStatus.MasterLabel);

                SyncGuard.inboundSyncIds.add(lead.Id);
                conversions.add(lc);
                conversionLeads.add(lead);
                conversionCustomerIds.add(customerId);
            } else {
                directCreates.add(data);
            }
        }

        // Bulk convert Leads.
        if (!conversions.isEmpty()) {
            List<Database.LeadConvertResult> results = Database.convertLead(conversions);
            enrichConvertedAccounts(results, conversionLeads, conversionCustomerIds);
        }

        // Bulk create Account + Contact + Opportunity for events with no Lead.
        if (!directCreates.isEmpty()) {
            createAccountsContactsOpportunities(directCreates);
        }
    }

    private void enrichConvertedAccounts(
            List<Database.LeadConvertResult> results,
            List<Lead> leads,
            List<String> customerIds) {
        List<Account> toUpdate = new List<Account>();

        for (Integer i = 0; i < results.size(); i++) {
            Database.LeadConvertResult result = results[i];

            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR,
                    'EpUserJoinedHandler: Lead conversion failed');
                continue;
            }

            Lead lead = leads[i];
            Account acc = new Account(
                Id = result.getAccountId(),
                Replicated_Customer_Id__c = customerIds[i]
            );

            if (String.isNotBlank(lead.Replicated_License_Type__c)) {
                acc.Replicated_License_Type__c = lead.Replicated_License_Type__c;
            }
            if (String.isNotBlank(lead.Replicated_Channel__c)) {
                acc.Replicated_Channel__c = lead.Replicated_Channel__c;
            }
            if (lead.Replicated_License_Expiry__c != null) {
                acc.Replicated_License_Expiry__c = lead.Replicated_License_Expiry__c;
            }

            SyncGuard.inboundSyncIds.add(acc.Id);
            toUpdate.add(acc);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            for (Database.SaveResult sr : saveResults) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.ERROR,
                        'EpUserJoinedHandler: Account enrichment failed');
                }
            }
        }
    }

    private void createAccountsContactsOpportunities(List<Map<String, Object>> dataList) {
        // Phase 1: Create all Accounts.
        List<Account> accounts = new List<Account>();
        for (Map<String, Object> data : dataList) {
            String customerName = (String) data.get('customer_name');
            String name = String.isNotBlank(customerName) ? customerName : 'Unknown';
            accounts.add(new Account(
                Name = name,
                Replicated_Customer_Id__c = (String) data.get('customer_id')
            ));
        }

        Savepoint sp = Database.setSavepoint();
        try {
            insert accounts;
            for (Account acc : accounts) {
                SyncGuard.inboundSyncIds.add(acc.Id);
            }

            // Phase 2: Create Contacts linked to their Accounts.
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < dataList.size(); i++) {
                Map<String, Object> data = dataList[i];
                String customerName = (String) data.get('customer_name');
                String name = String.isNotBlank(customerName) ? customerName : 'Unknown';
                contacts.add(new Contact(
                    LastName = name,
                    Email = (String) data.get('joined_email'),
                    AccountId = accounts[i].Id
                ));
            }
            insert contacts;
            for (Contact c : contacts) {
                SyncGuard.inboundSyncIds.add(c.Id);
            }

            // Phase 3: Create Opportunities linked to their Accounts.
            List<Opportunity> opps = new List<Opportunity>();
            for (Integer i = 0; i < dataList.size(); i++) {
                Map<String, Object> data = dataList[i];
                String customerName = (String) data.get('customer_name');
                String name = String.isNotBlank(customerName) ? customerName : 'Unknown';
                opps.add(new Opportunity(
                    Name = name + ' - Trial Conversion',
                    AccountId = accounts[i].Id,
                    StageName = 'Qualification',
                    CloseDate = Date.today().addDays(30)
                ));
            }
            insert opps;
            for (Opportunity opp : opps) {
                SyncGuard.inboundSyncIds.add(opp.Id);
            }
        } catch (DmlException e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR,
                'EpUserJoinedHandler: failed to create Account/Contact/Opportunity: ' + e.getMessage());
        }
    }
}
