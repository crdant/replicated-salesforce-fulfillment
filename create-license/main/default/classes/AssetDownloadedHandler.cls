// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Account and Order records.
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
            Map<String, Object> data;
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
                data = (Map<String, Object>) parsed.get('data');
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'AssetDownloadedHandler: malformed payload, skipping');
                continue;
            }

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'AssetDownloadedHandler: missing data in payload');
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

        // Bulk query Accounts by Replicated customer ID.
        Map<String, Account> accountsByCustomerId = new Map<String, Account>();
        for (Account acc : [
            SELECT Id, Replicated_Customer_Id__c
            FROM Account
            WHERE Replicated_Customer_Id__c IN :customerIds
        ]) {
            accountsByCustomerId.put(acc.Replicated_Customer_Id__c, acc);
        }

        // Build download records and collect paid event data for order fulfillment.
        List<Replicated_Download__c> downloads = new List<Replicated_Download__c>();
        List<Map<String, Object>> paidEvents = new List<Map<String, Object>>();
        Set<Id> paidAccountIds = new Set<Id>();
        Set<String> paidAppIds = new Set<String>();

        for (Map<String, Object> data : dataList) {
            String customerId = (String) data.get('customer_id');
            Account acc = accountsByCustomerId.get(customerId);
            if (acc == null) {
                System.debug(LoggingLevel.WARN,
                    'AssetDownloadedHandler: no Account found for customer_id, skipping');
                continue;
            }

            DateTime downloadedAt = parseDateTime((String) data.get('downloaded_at'));

            downloads.add(new Replicated_Download__c(
                Account__c = acc.Id,
                Asset_Type__c = (String) data.get('asset_type'),
                Asset_Name__c = (String) data.get('asset_name'),
                Asset_Version__c = (String) data.get('asset_version'),
                Channel_Name__c = (String) data.get('channel_name'),
                License_Type__c = (String) data.get('license_type'),
                Downloaded_At__c = downloadedAt,
                Replicated_Customer_Id__c = customerId,
                App_Name__c = (String) data.get('app_name')
            ));

            String licenseType = (String) data.get('license_type');
            String appId = (String) data.get('app_id');
            if (licenseType == 'paid' && String.isNotBlank(appId)) {
                paidEvents.add(data);
                paidAccountIds.add(acc.Id);
                paidAppIds.add(appId);
            }
        }

        // Bulk insert download records.
        // No SyncGuard needed — no outbound triggers on Replicated_Download__c.
        if (!downloads.isEmpty()) {
            insert downloads;
        }

        // Order fulfillment for paid downloads.
        if (!paidEvents.isEmpty()) {
            fulfillOrders(paidEvents, accountsByCustomerId, paidAccountIds, paidAppIds);
        }
    }

    private void fulfillOrders(
            List<Map<String, Object>> paidEvents,
            Map<String, Account> accountsByCustomerId,
            Set<Id> paidAccountIds,
            Set<String> paidAppIds) {

        // Query unfulfilled licensed Orders for relevant Accounts.
        List<Order> unfulfilled = [
            SELECT Id, AccountId, CreatedDate, OpportunityId
            FROM Order
            WHERE AccountId IN :paidAccountIds
              AND LicenseId__c != null
              AND FulfilledAt__c = null
            ORDER BY CreatedDate ASC
        ];

        if (unfulfilled.isEmpty()) {
            return;
        }

        // Resolve which app each Order belongs to via OpportunityLineItem → Product2.
        Set<Id> oppIds = new Set<Id>();
        for (Order o : unfulfilled) {
            if (o.OpportunityId != null) {
                oppIds.add(o.OpportunityId);
            }
        }

        Map<Id, String> oppToAppId = new Map<Id, String>();
        if (!oppIds.isEmpty()) {
            for (OpportunityLineItem oli : [
                SELECT OpportunityId, Product2.Application__c
                FROM OpportunityLineItem
                WHERE OpportunityId IN :oppIds
                  AND Product2.Application__c IN :paidAppIds
                  AND Product2.IsAddOn__c = false
            ]) {
                oppToAppId.put(oli.OpportunityId, oli.Product2.Application__c);
            }
        }

        // Build map: (AccountId:appId) → oldest unfulfilled Order.
        Map<String, Order> ordersByKey = new Map<String, Order>();
        for (Order o : unfulfilled) {
            String appId = oppToAppId.get(o.OpportunityId);
            if (appId == null) {
                continue;
            }
            String key = o.AccountId + ':' + appId;
            if (!ordersByKey.containsKey(key)) {
                ordersByKey.put(key, o);
            }
        }

        // Match paid events to orders and set FulfilledAt__c.
        List<Order> toUpdate = new List<Order>();
        Set<Id> updatedOrderIds = new Set<Id>();

        for (Map<String, Object> data : paidEvents) {
            String customerId = (String) data.get('customer_id');
            Account acc = accountsByCustomerId.get(customerId);
            if (acc == null) {
                continue;
            }

            String appId = (String) data.get('app_id');
            String key = acc.Id + ':' + appId;
            Order o = ordersByKey.get(key);
            if (o == null || updatedOrderIds.contains(o.Id)) {
                continue;
            }

            DateTime downloadedAt = parseDateTime((String) data.get('downloaded_at'));
            o.FulfilledAt__c = downloadedAt;
            SyncGuard.inboundSyncIds.add(o.Id);
            toUpdate.add(o);
            updatedOrderIds.add(o.Id);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static DateTime parseDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return DateTime.now();
        }
        try {
            return (DateTime) JSON.deserialize('"' + dateTimeStr + '"', DateTime.class);
        } catch (Exception e) {
            return DateTime.now();
        }
    }
}
