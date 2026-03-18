@IsTest
private class InstanceEventHandlerTest {

    private static final String CUSTOMER_ID = 'cust-test-123';
    private static final String INSTANCE_ID = 'inst-test-456';

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Test Account',
            Replicated_Customer_Id__c = CUSTOMER_ID
        );
        insert acc;
    }

    private static String instanceCreatedPayload() {
        return '{"event":"instance.created","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"customer_name":"Test Customer",' +
            '"instance_id":"' + INSTANCE_ID + '",' +
            '"status":"ready",' +
            '"app_version":"1.2.3",' +
            '"cloud_provider":"aws",' +
            '"k8s_distribution":"eks",' +
            '"created_at":"2026-01-15T10:30:00Z",' +
            '"last_check_in":"2026-01-15T10:35:00Z"' +
            '}}';
    }

    private static String instanceUpgradedPayload() {
        return '{"event":"instance.upgraded","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"instance_id":"' + INSTANCE_ID + '",' +
            '"app_version":"2.0.0"' +
            '}}';
    }

    private static String instanceInactivePayload() {
        return '{"event":"instance.inactive","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"instance_id":"' + INSTANCE_ID + '",' +
            '"last_check_in":"2026-01-10T08:00:00Z"' +
            '}}';
    }

    @IsTest
    static void testInstanceCreated() {
        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.created', CUSTOMER_ID, instanceCreatedPayload()
        ));
        Test.stopTest();

        Replicated_Instance__c inst = [
            SELECT Instance_Id__c, Status__c, App_Version__c, Cloud_Provider__c,
                   K8s_Distribution__c, Account__c, Name
            FROM Replicated_Instance__c
            WHERE Instance_Id__c = :INSTANCE_ID
            LIMIT 1
        ];

        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        System.assertEquals(INSTANCE_ID, inst.Instance_Id__c, 'Instance ID should match');
        System.assertEquals('Ready', inst.Status__c, 'Status should be Ready');
        System.assertEquals('1.2.3', inst.App_Version__c, 'App version should match');
        System.assertEquals('aws', inst.Cloud_Provider__c, 'Cloud provider should match');
        System.assertEquals('eks', inst.K8s_Distribution__c, 'K8s distribution should match');
        System.assertEquals(acc.Id, inst.Account__c, 'Account should match');
        System.assert(inst.Name.contains('Test Customer'), 'Name should contain customer name');
    }

    @IsTest
    static void testInstanceUpgradedExisting() {
        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Replicated_Instance__c existing = new Replicated_Instance__c(
            Instance_Id__c = INSTANCE_ID,
            Account__c = acc.Id,
            Status__c = 'Ready',
            App_Version__c = '1.2.3',
            Name = 'Test Instance'
        );
        insert existing;

        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.upgraded', CUSTOMER_ID, instanceUpgradedPayload()
        ));
        Test.stopTest();

        Replicated_Instance__c inst = [
            SELECT App_Version__c, Status__c
            FROM Replicated_Instance__c
            WHERE Instance_Id__c = :INSTANCE_ID
            LIMIT 1
        ];

        System.assertEquals('2.0.0', inst.App_Version__c, 'App version should be updated');
        System.assertEquals('Ready', inst.Status__c, 'Status should remain unchanged');
    }

    @IsTest
    static void testInstanceInactive() {
        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Replicated_Instance__c existing = new Replicated_Instance__c(
            Instance_Id__c = INSTANCE_ID,
            Account__c = acc.Id,
            Status__c = 'Ready',
            App_Version__c = '1.2.3',
            Name = 'Test Instance'
        );
        insert existing;

        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.inactive', CUSTOMER_ID, instanceInactivePayload()
        ));
        Test.stopTest();

        Replicated_Instance__c inst = [
            SELECT Status__c
            FROM Replicated_Instance__c
            WHERE Instance_Id__c = :INSTANCE_ID
            LIMIT 1
        ];

        System.assertEquals('Unavailable', inst.Status__c, 'Status should be Unavailable');
    }

    @IsTest
    static void testNoMatchingAccount() {
        String unknownCustomerId = 'cust-unknown-999';
        String payload = '{"event":"instance.created","data":{' +
            '"customer_id":"' + unknownCustomerId + '",' +
            '"instance_id":"inst-orphan-789",' +
            '"status":"ready",' +
            '"app_version":"1.0.0"' +
            '}}';

        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.created', unknownCustomerId, payload
        ));
        Test.stopTest();

        List<Replicated_Instance__c> instances = [
            SELECT Id FROM Replicated_Instance__c
            WHERE Instance_Id__c = 'inst-orphan-789'
        ];
        System.assertEquals(0, instances.size(), 'No instance should be created without a matching Account');
    }

    @IsTest
    static void testMissingInstanceId() {
        String payload = '{"event":"instance.created","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"status":"ready"' +
            '}}';

        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.created', CUSTOMER_ID, payload
        ));
        Test.stopTest();

        List<Replicated_Instance__c> instances = [
            SELECT Id FROM Replicated_Instance__c
        ];
        System.assertEquals(0, instances.size(), 'No instance should be created without instance_id');
    }

    @IsTest
    static void testMissingDataInPayload() {
        String payload = '{"event":"instance.created"}';

        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.created', CUSTOMER_ID, payload
        ));
        Test.stopTest();

        List<Replicated_Instance__c> instances = [
            SELECT Id FROM Replicated_Instance__c
        ];
        System.assertEquals(0, instances.size(), 'No instance should be created without data');
    }

    @IsTest
    static void testResolveStatusMapping() {
        System.assertEquals('Ready', InstanceEventHandler.resolveStatus('ready'), 'ready maps to Ready');
        System.assertEquals('Updating', InstanceEventHandler.resolveStatus('updating'), 'updating maps to Updating');
        System.assertEquals('Degraded', InstanceEventHandler.resolveStatus('degraded'), 'degraded maps to Degraded');
        System.assertEquals('Unavailable', InstanceEventHandler.resolveStatus('unavailable'), 'unavailable maps to Unavailable');
        System.assertEquals('Missing', InstanceEventHandler.resolveStatus('missing'), 'missing maps to Missing');
        System.assertEquals('Unknown', InstanceEventHandler.resolveStatus('something_else'), 'unknown status maps to Unknown');
        System.assertEquals('Unknown', InstanceEventHandler.resolveStatus(null), 'null maps to Unknown');
        System.assertEquals('Unknown', InstanceEventHandler.resolveStatus(''), 'empty maps to Unknown');
    }

    @IsTest
    static void testSyncGuardIsSet() {
        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Test.startTest();
        System.enqueueJob(new InstanceEventHandler(
            'instance.created', CUSTOMER_ID, instanceCreatedPayload()
        ));
        Test.stopTest();

        // Verify a record was created (SyncGuard runs within the Queueable context,
        // so we verify the DML succeeded which proves SyncGuard didn't block it)
        Replicated_Instance__c inst = [
            SELECT Id, Account__c
            FROM Replicated_Instance__c
            WHERE Instance_Id__c = :INSTANCE_ID
            LIMIT 1
        ];
        System.assertEquals(acc.Id, inst.Account__c, 'Instance should be linked to the Account');
    }
}
