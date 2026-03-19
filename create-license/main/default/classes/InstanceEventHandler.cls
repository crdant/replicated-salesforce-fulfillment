// Runs without sharing: system-to-system webhook handler needs
// unrestricted access to Account and Instance records.
public without sharing class InstanceEventHandler implements Queueable {
    private List<Replicated_Webhook__e> events;

    public InstanceEventHandler(List<Replicated_Webhook__e> events) {
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
            SELECT Id, Replicated_Customer_Id__c FROM Account
            WHERE Replicated_Customer_Id__c IN :customerIds
        ]) {
            accountsByCustomerId.put(acc.Replicated_Customer_Id__c, acc);
        }

        // Use a Map to merge multiple events for the same instance. Salesforce
        // rejects upsert lists with duplicate external IDs, and later events in
        // the batch should layer their fields on top of earlier ones.
        Map<String, Replicated_Instance__c> instancesByExternalId =
            new Map<String, Replicated_Instance__c>();

        for (Replicated_Webhook__e event : this.events) {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(event.Payload__c);
            Map<String, Object> data = (Map<String, Object>) parsed.get('data');

            if (data == null) {
                System.debug(LoggingLevel.WARN, 'InstanceEventHandler: missing data in payload');
                continue;
            }

            String instanceId = (String) data.get('instance_id');
            if (String.isBlank(instanceId)) {
                System.debug(LoggingLevel.WARN, 'InstanceEventHandler: missing instance_id in payload');
                continue;
            }

            Account acc = accountsByCustomerId.get(event.Customer_Id__c);
            if (acc == null) {
                System.debug(LoggingLevel.WARN,
                    'InstanceEventHandler: no Account found for Replicated customer');
                continue;
            }

            SyncGuard.inboundSyncIds.add(acc.Id);

            Replicated_Instance__c instance = instancesByExternalId.get(instanceId);
            if (instance == null) {
                instance = new Replicated_Instance__c(
                    Instance_Id__c = instanceId,
                    Account__c = acc.Id
                );
                instancesByExternalId.put(instanceId, instance);
            }

            if (event.Event_Type__c == ReplicatedEventType.INSTANCE_CREATED) {
                instance.Status__c = resolveStatus((String) data.get('status'));
                instance.App_Version__c = (String) data.get('app_version');
                instance.Cloud_Provider__c = (String) data.get('cloud_provider');
                instance.K8s_Distribution__c = (String) data.get('k8s_distribution');
                instance.First_Check_In__c = parseDateTime((String) data.get('created_at'));
                instance.Last_Check_In__c = parseDateTime((String) data.get('last_check_in'));
                instance.Name = buildInstanceName(instanceId, (String) data.get('customer_name'));
            } else if (event.Event_Type__c == ReplicatedEventType.INSTANCE_UPGRADE_COMPLETED) {
                instance.App_Version__c = (String) data.get('app_version');
                instance.Last_Check_In__c = DateTime.now();
            } else if (event.Event_Type__c == ReplicatedEventType.INSTANCE_INACTIVE) {
                instance.Status__c = 'Unavailable';
                instance.Last_Check_In__c = parseDateTime((String) data.get('last_check_in'));
            }
        }

        if (!instancesByExternalId.isEmpty()) {
            upsert instancesByExternalId.values() Instance_Id__c;
        }
    }

    @TestVisible
    private static String resolveStatus(String replicatedStatus) {
        if (String.isBlank(replicatedStatus)) {
            return 'Unknown';
        }

        Map<String, String> statusMap = new Map<String, String>{
            'ready' => 'Ready',
            'updating' => 'Updating',
            'degraded' => 'Degraded',
            'unavailable' => 'Unavailable',
            'missing' => 'Missing'
        };

        String mapped = statusMap.get(replicatedStatus.toLowerCase());
        return mapped != null ? mapped : 'Unknown';
    }

    private static DateTime parseDateTime(String isoString) {
        if (String.isBlank(isoString)) {
            return null;
        }
        try {
            return (DateTime) JSON.deserialize('"' + isoString + '"', DateTime.class);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'InstanceEventHandler: failed to parse datetime: ' + isoString);
            return null;
        }
    }

    private static String buildInstanceName(String instanceId, String customerName) {
        if (String.isNotBlank(customerName)) {
            String name = customerName + ' - ' + instanceId;
            return name.length() > 80 ? name.substring(0, 80) : name;
        }
        return instanceId.length() > 80 ? instanceId.substring(0, 80) : instanceId;
    }
}
