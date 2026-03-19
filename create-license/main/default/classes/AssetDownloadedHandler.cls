// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Account, Lead, Contact, and Opportunity records.
public without sharing class AssetDownloadedHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public AssetDownloadedHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Parse all payloads and collect customer IDs for bulk lookup.
        List<Map<String, Object>> dataList = new List<Map<String, Object>>();
        Set<String> customerIds = new Set<String>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
            Map<String, Object> data = (Map<String, Object>) parsed.get('data');

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'AssetDownloadedHandler: missing data in payload');
                continue;
            }

            dataList.add(data);
            String customerId = (String) data.get('customer_id');
            if (String.isNotBlank(customerId)) {
                customerIds.add(customerId);
            }
        }

        // Bulk query: existing Accounts by customer ID (for idempotency).
        Set<String> existingAccountCustomerIds = new Set<String>();
        for (Account acc : [
            SELECT Replicated_Customer_Id__c FROM Account
            WHERE Replicated_Customer_Id__c IN :customerIds
        ]) {
            existingAccountCustomerIds.add(acc.Replicated_Customer_Id__c);
        }

        // Bulk query: unconverted Leads by customer ID.
        Map<String, Lead> leadsByCustomerId = new Map<String, Lead>();
        for (Lead l : [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
                   Replicated_Channel__c, Replicated_License_Expiry__c
            FROM Lead
            WHERE Replicated_Customer_Id__c IN :customerIds AND IsConverted = false
        ]) {
            leadsByCustomerId.put(l.Replicated_Customer_Id__c, l);
        }

        // Cache the converted status label (org metadata, never changes at runtime).
        LeadStatus convertedStatus = [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        // Process each event: convert Lead or create records directly.
        List<Database.LeadConvert> conversions = new List<Database.LeadConvert>();
        // Track which Lead maps to which customer ID for post-conversion enrichment.
        List<Lead> conversionLeads = new List<Lead>();
        List<String> conversionCustomerIds = new List<String>();

        // Track direct-create data for events with no Lead.
        List<Map<String, Object>> directCreates = new List<Map<String, Object>>();

        for (Map<String, Object> data : dataList) {
            String customerId = (String) data.get('customer_id');

            // Idempotent: skip if Account already exists for this customer.
            if (existingAccountCustomerIds.contains(customerId)) {
                continue;
            }

            Lead lead = leadsByCustomerId.get(customerId);

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
                    'AssetDownloadedHandler: Lead conversion failed for Lead ' + leads[i].Id);
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
            update toUpdate;
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
                    Email = (String) data.get('email'),
                    AccountId = accounts[i].Id
                ));
            }
            insert contacts;

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
        } catch (DmlException e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR,
                'AssetDownloadedHandler: failed to create Account/Contact/Opportunity: ' + e.getMessage());
        }
    }
}
