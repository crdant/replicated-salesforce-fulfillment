// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Account records.
public without sharing class CustomerUpdatedHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public CustomerUpdatedHandler(List<Replicated_Webhook__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        // Parse all payloads and collect customer IDs for bulk Account lookup.
        List<Map<String, Object>> dataList = new List<Map<String, Object>>();
        Set<String> customerIds = new Set<String>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> data;
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
                data = (Map<String, Object>) parsed.get('data');
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'CustomerUpdatedHandler: malformed payload, skipping');
                continue;
            }

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'CustomerUpdatedHandler: missing data in payload');
                continue;
            }

            String customerId = (String) data.get('customer_id');
            if (String.isBlank(customerId)) {
                continue;
            }

            dataList.add(data);
            customerIds.add(customerId);
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Single SOQL: find all Accounts by Replicated customer ID.
        Map<String, Account> accountsByCustomerId = new Map<String, Account>();
        for (Account acc : [
            SELECT Id, Replicated_Customer_Id__c
            FROM Account
            WHERE Replicated_Customer_Id__c IN :customerIds
        ]) {
            accountsByCustomerId.put(acc.Replicated_Customer_Id__c, acc);
        }

        List<Account> toUpdate = new List<Account>();

        for (Map<String, Object> data : dataList) {
            String customerId = (String) data.get('customer_id');
            Account acc = accountsByCustomerId.get(customerId);
            if (acc == null) {
                System.debug(LoggingLevel.WARN,
                    'CustomerUpdatedHandler: no matching Account found, skipping event');
                continue;
            }

            Boolean changed = false;

            // Sync customer_name only if old_customer_name differs.
            String customerName = (String) data.get('customer_name');
            String oldCustomerName = (String) data.get('old_customer_name');
            if (customerName != null && oldCustomerName != null && customerName != oldCustomerName) {
                acc.Name = customerName;
                changed = true;
            }

            // Sync license_type only if old_license_type differs.
            String licenseType = (String) data.get('license_type');
            String oldLicenseType = (String) data.get('old_license_type');
            if (licenseType != null && oldLicenseType != null && licenseType != oldLicenseType) {
                acc.Replicated_License_Type__c = licenseType;
                changed = true;
            }

            // Sync channel_name only if channel_changed is true.
            Boolean channelChanged = (Boolean) data.get('channel_changed');
            String channelName = (String) data.get('channel_name');
            if (channelChanged == true && channelName != null) {
                acc.Replicated_Channel__c = channelName;
                changed = true;
            }

            // Sync expires_at only if expiration_changed is true.
            Boolean expirationChanged = (Boolean) data.get('expiration_changed');
            if (expirationChanged == true) {
                Date expiryDate = WebhookPayloadUtils.parseDate((String) data.get('expires_at'));
                if (expiryDate != null) {
                    acc.Replicated_License_Expiry__c = expiryDate;
                    changed = true;
                }
            }

            if (changed) {
                SyncGuard.inboundSyncIds.add(acc.Id);
                toUpdate.add(acc);
            }
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(toUpdate, false);
            for (Database.SaveResult result : results) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.WARN,
                        'CustomerUpdatedHandler: partial update failure, skipping record');
                }
            }
        }
    }

}
