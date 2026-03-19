// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Account records and Task creation.
public without sharing class LicenseExpiringHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public LicenseExpiringHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Collect all customer IDs to query Accounts in bulk.
        Set<String> customerIds = new Set<String>();
        for (Replicated_Webhook__e event : this.events) {
            if (String.isNotBlank(event.Customer_Id__c)) {
                customerIds.add(event.Customer_Id__c);
            }
        }

        Map<String, Account> accountsByCustomerId = new Map<String, Account>();
        for (Account acc : [
            SELECT Id, OwnerId, Name, Replicated_Customer_Id__c FROM Account
            WHERE Replicated_Customer_Id__c IN :customerIds
        ]) {
            accountsByCustomerId.put(acc.Replicated_Customer_Id__c, acc);
        }

        List<Task> tasks = new List<Task>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
            Map<String, Object> data = (Map<String, Object>) parsed.get('data');

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'LicenseExpiringHandler: missing data in payload');
                continue;
            }

            Account acc = accountsByCustomerId.get(event.Customer_Id__c);
            if (acc == null) {
                System.debug(LoggingLevel.WARN,
                    'LicenseExpiringHandler: no Account found for Replicated customer');
                continue;
            }

            SyncGuard.inboundSyncIds.add(acc.Id);

            String customerName = (String) data.get('customer_name');
            String expiresAt = (String) data.get('expires_at');
            Date expiryDate = parseDate(expiresAt);

            String subject = 'Trial license expiring for ' +
                (String.isNotBlank(customerName) ? customerName : acc.Name);

            String description = 'License expires on ' +
                (String.isNotBlank(expiresAt) ? expiresAt : 'unknown date') +
                '. Follow up to discuss conversion.';

            Date activityDate = Date.today();
            if (expiryDate != null) {
                Date sevenDaysBefore = expiryDate.addDays(-7);
                if (sevenDaysBefore > Date.today()) {
                    activityDate = sevenDaysBefore;
                }
            }

            tasks.add(new Task(
                WhatId = acc.Id,
                OwnerId = acc.OwnerId,
                Subject = subject,
                Description = description,
                ActivityDate = activityDate,
                Status = 'Not Started',
                Priority = 'High'
            ));
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    private static Date parseDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            // Handle ISO datetime strings by extracting the date portion
            if (dateString.contains('T')) {
                dateString = dateString.substringBefore('T');
            }
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'LicenseExpiringHandler: failed to parse date: ' + dateString);
            return null;
        }
    }
}
