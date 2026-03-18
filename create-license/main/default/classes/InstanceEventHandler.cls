public class InstanceEventHandler implements Queueable {
    private String eventType;
    private String customerId;
    private String payload;

    public InstanceEventHandler(String eventType, String customerId, String payload) {
        this.eventType = eventType;
        this.customerId = customerId;
        this.payload = payload;
    }

    public void execute(QueueableContext context) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(this.payload);
        Map<String, Object> data = (Map<String, Object>) parsed.get('data');

        if (data == null) {
            System.debug(LoggingLevel.WARN, 'InstanceEventHandler: missing data in payload');
            return;
        }

        String instanceId = (String) data.get('instance_id');
        if (String.isBlank(instanceId)) {
            System.debug(LoggingLevel.WARN, 'InstanceEventHandler: missing instance_id in payload');
            return;
        }

        List<Account> accounts = [
            SELECT Id FROM Account
            WHERE Replicated_Customer_Id__c = :this.customerId
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'InstanceEventHandler: no Account found for Replicated customer ' + this.customerId);
            return;
        }

        Account acc = accounts[0];
        SyncGuard.inboundSyncIds.add(acc.Id);

        Replicated_Instance__c instance = new Replicated_Instance__c(
            Instance_Id__c = instanceId,
            Account__c = acc.Id
        );

        if (this.eventType == 'instance.created') {
            instance.Status__c = resolveStatus((String) data.get('status'));
            instance.App_Version__c = (String) data.get('app_version');
            instance.Cloud_Provider__c = (String) data.get('cloud_provider');
            instance.K8s_Distribution__c = (String) data.get('k8s_distribution');
            instance.First_Check_In__c = parseDateTime((String) data.get('created_at'));
            instance.Last_Check_In__c = parseDateTime((String) data.get('last_check_in'));
            instance.Name = buildInstanceName(instanceId, (String) data.get('customer_name'));
        } else if (this.eventType == 'instance.upgraded') {
            instance.App_Version__c = (String) data.get('app_version');
            instance.Last_Check_In__c = DateTime.now();
        } else if (this.eventType == 'instance.inactive') {
            instance.Status__c = 'Unavailable';
            instance.Last_Check_In__c = parseDateTime((String) data.get('last_check_in'));
        }

        upsert instance Instance_Id__c;
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
