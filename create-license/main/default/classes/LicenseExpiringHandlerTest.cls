@IsTest
private class LicenseExpiringHandlerTest {

    private static final String CUSTOMER_ID = 'cust-test-456';

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Expiring License Account',
            Replicated_Customer_Id__c = CUSTOMER_ID
        );
        insert acc;
    }

    private static Replicated_Webhook__e buildEvent(String payload) {
        return new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.CUSTOMER_LICENSE_EXPIRING,
            Customer_Id__c = CUSTOMER_ID,
            Payload__c = payload
        );
    }

    private static String expiringPayload(String expiresAt) {
        return '{"event":"customer.license_expiring","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"customer_name":"Acme Corp",' +
            '"expires_at":"' + expiresAt + '"' +
            '}}';
    }

    @IsTest
    static void testLicenseExpiringCreatesTask() {
        String payload = expiringPayload('2026-04-15');

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{ buildEvent(payload) }
        ));
        Test.stopTest();

        Account acc = [SELECT Id, OwnerId FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        List<Task> tasks = [
            SELECT WhatId, OwnerId, Subject, Description, ActivityDate, Status, Priority
            FROM Task
            WHERE WhatId = :acc.Id
        ];

        System.assertEquals(1, tasks.size(), 'One task should be created');

        Task t = tasks[0];
        System.assertEquals(acc.Id, t.WhatId, 'Task should be linked to Account');
        System.assertEquals(acc.OwnerId, t.OwnerId, 'Task should be assigned to Account owner');
        System.assert(t.Subject.contains('Acme Corp'), 'Subject should contain customer name');
        System.assert(t.Description.contains('2026-04-15'), 'Description should contain expiry date');
        System.assert(t.Description.contains('Follow up'), 'Description should mention follow up');
        System.assertEquals(Date.valueOf('2026-04-08'), t.ActivityDate, 'Activity date should be 7 days before expiry');
        System.assertEquals('Not Started', t.Status, 'Status should be Not Started');
        System.assertEquals('High', t.Priority, 'Priority should be High');
    }

    @IsTest
    static void testLicenseExpiringWithDateTimeFormat() {
        String payload = expiringPayload('2026-05-20T23:59:59Z');

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{ buildEvent(payload) }
        ));
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Task t = [SELECT ActivityDate FROM Task WHERE WhatId = :acc.Id LIMIT 1];
        System.assertEquals(Date.valueOf('2026-05-13'), t.ActivityDate,
            'Activity date should be 7 days before expiry even with datetime format');
    }

    @IsTest
    static void testNoMatchingAccount() {
        String unknownCustomerId = 'cust-unknown-999';
        String payload = '{"event":"customer.license_expiring","data":{' +
            '"customer_id":"' + unknownCustomerId + '",' +
            '"customer_name":"Unknown Corp",' +
            '"expires_at":"2026-04-15"' +
            '}}';

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{
                new Replicated_Webhook__e(
                    Event_Type__c = ReplicatedEventType.CUSTOMER_LICENSE_EXPIRING,
                    Customer_Id__c = unknownCustomerId,
                    Payload__c = payload
                )
            }
        ));
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task WHERE Subject LIKE '%Unknown Corp%'];
        System.assertEquals(0, tasks.size(), 'No task should be created without a matching Account');
    }

    @IsTest
    static void testMissingCustomerNameFallsBackToAccountName() {
        String payload = '{"event":"customer.license_expiring","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"expires_at":"2026-04-15"' +
            '}}';

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{ buildEvent(payload) }
        ));
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Task t = [SELECT Subject FROM Task WHERE WhatId = :acc.Id LIMIT 1];
        System.assert(t.Subject.contains('Expiring License Account'),
            'Subject should fall back to Account name when customer_name is missing');
    }

    @IsTest
    static void testMissingExpiresAt() {
        String payload = '{"event":"customer.license_expiring","data":{' +
            '"customer_id":"' + CUSTOMER_ID + '",' +
            '"customer_name":"Acme Corp"' +
            '}}';

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{ buildEvent(payload) }
        ));
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Task t = [SELECT ActivityDate, Description FROM Task WHERE WhatId = :acc.Id LIMIT 1];
        System.assertEquals(Date.today(), t.ActivityDate,
            'Activity date should default to today when expires_at is missing');
        System.assert(t.Description.contains('unknown date'),
            'Description should indicate unknown date');
    }

    @IsTest
    static void testMissingDataInPayload() {
        String payload = '{"event":"customer.license_expiring"}';

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{ buildEvent(payload) }
        ));
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :acc.Id];
        System.assertEquals(0, tasks.size(), 'No task should be created without data in payload');
    }

    @IsTest
    static void testExpiryInPastUsesToday() {
        String payload = expiringPayload('2025-01-01');

        Test.startTest();
        System.enqueueJob(new LicenseExpiringHandler(
            new List<Replicated_Webhook__e>{ buildEvent(payload) }
        ));
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = :CUSTOMER_ID LIMIT 1];

        Task t = [SELECT ActivityDate FROM Task WHERE WhatId = :acc.Id LIMIT 1];
        System.assertEquals(Date.today(), t.ActivityDate,
            'Activity date should be today when computed date is in the past');
    }
}
