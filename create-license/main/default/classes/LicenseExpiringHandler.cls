public class LicenseExpiringHandler implements Queueable {
    private String customerId;
    private String payload;

    public LicenseExpiringHandler(String customerId, String payload) {
        this.customerId = customerId;
        this.payload = payload;
    }

    public void execute(QueueableContext context) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(this.payload);
        Map<String, Object> data = (Map<String, Object>) parsed.get('data');

        if (data == null) {
            System.debug(LoggingLevel.WARN, 'LicenseExpiringHandler: missing data in payload');
            return;
        }

        List<Account> accounts = [
            SELECT Id, OwnerId, Name FROM Account
            WHERE Replicated_Customer_Id__c = :this.customerId
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'LicenseExpiringHandler: no Account found for Replicated customer ' + this.customerId);
            return;
        }

        Account acc = accounts[0];
        SyncGuard.inboundSyncIds.add(acc.Id);

        String customerName = (String) data.get('customer_name');
        String expiresAt = (String) data.get('expires_at');
        Date expiryDate = parseDate(expiresAt);

        String subject = 'Trial license expiring for ' +
            (String.isNotBlank(customerName) ? customerName : acc.Name);

        String description = 'License expires on ' +
            (String.isNotBlank(expiresAt) ? expiresAt : 'unknown date') +
            '. Follow up to discuss conversion.';

        Date activityDate;
        if (expiryDate != null) {
            activityDate = expiryDate.addDays(-7);
            if (activityDate < Date.today()) {
                activityDate = Date.today();
            }
        } else {
            activityDate = Date.today();
        }

        Task followUp = new Task(
            WhatId = acc.Id,
            OwnerId = acc.OwnerId,
            Subject = subject,
            Description = description,
            ActivityDate = activityDate,
            Status = 'Not Started',
            Priority = 'High'
        );
        insert followUp;
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
