@IsTest
private class CustomerUpdatedHandlerTest {

    private static Replicated_Webhook__e buildEvent(Map<String, Object> data) {
        Map<String, Object> payload = new Map<String, Object>{
            'event' => ReplicatedEventType.CUSTOMER_UPDATED,
            'data' => data
        };
        return new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.CUSTOMER_UPDATED,
            Payload__c = JSON.serialize(payload)
        );
    }

    private static Account createTestAccount(String customerId, String name) {
        Account acc = new Account(
            Name = name,
            Replicated_Customer_Id__c = customerId,
            Replicated_License_Type__c = 'trial',
            Replicated_Channel__c = 'Stable',
            Replicated_License_Expiry__c = Date.valueOf('2026-12-31')
        );
        insert acc;
        return acc;
    }

    @IsTest
    static void testSyncsCustomerName() {
        Account acc = createTestAccount('cust_100', 'Old Name');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_100',
                'customer_name' => 'New Name',
                'old_customer_name' => 'Old Name',
                'license_type' => 'trial',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        Account updated = [SELECT Name, Replicated_License_Type__c, Replicated_Channel__c,
                                  Replicated_License_Expiry__c
                           FROM Account WHERE Id = :acc.Id];
        System.assertEquals('New Name', updated.Name, 'Name should be updated');
        System.assertEquals('trial', updated.Replicated_License_Type__c, 'License type should be unchanged');
        System.assertEquals('Stable', updated.Replicated_Channel__c, 'Channel should be unchanged');
        System.assertEquals(Date.valueOf('2026-12-31'), updated.Replicated_License_Expiry__c,
            'Expiry should be unchanged');
    }

    @IsTest
    static void testSyncsLicenseType() {
        Account acc = createTestAccount('cust_200', 'Acme Corp');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_200',
                'customer_name' => 'Acme Corp',
                'old_customer_name' => 'Acme Corp',
                'license_type' => 'paid',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        Account updated = [SELECT Replicated_License_Type__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('paid', updated.Replicated_License_Type__c, 'License type should be updated');
    }

    @IsTest
    static void testSyncsChannel() {
        Account acc = createTestAccount('cust_300', 'Channel Corp');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_300',
                'customer_name' => 'Channel Corp',
                'old_customer_name' => 'Channel Corp',
                'license_type' => 'trial',
                'old_license_type' => 'trial',
                'channel_changed' => true,
                'channel_name' => 'Beta',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        Account updated = [SELECT Replicated_Channel__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Beta', updated.Replicated_Channel__c, 'Channel should be updated');
    }

    @IsTest
    static void testSyncsExpiry() {
        Account acc = createTestAccount('cust_400', 'Expiry Corp');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_400',
                'customer_name' => 'Expiry Corp',
                'old_customer_name' => 'Expiry Corp',
                'license_type' => 'trial',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => true,
                'expires_at' => '2027-06-15T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        Account updated = [SELECT Replicated_License_Expiry__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(Date.valueOf('2027-06-15'), updated.Replicated_License_Expiry__c,
            'Expiry should be updated');
    }

    @IsTest
    static void testNoChangeNoOp() {
        Account acc = createTestAccount('cust_500', 'Unchanged Corp');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_500',
                'customer_name' => 'Unchanged Corp',
                'old_customer_name' => 'Unchanged Corp',
                'license_type' => 'trial',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        // Verify SyncGuard was NOT populated (no update was needed).
        System.assert(!SyncGuard.inboundSyncIds.contains(acc.Id),
            'SyncGuard should not contain Account Id when nothing changed');
    }

    @IsTest
    static void testNoMatchingAccount() {
        // No Account exists for this customer_id -- handler should not throw.
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_nonexistent',
                'customer_name' => 'Ghost Corp',
                'old_customer_name' => 'Old Ghost',
                'license_type' => 'trial',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        List<Account> accounts = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = 'cust_nonexistent'];
        System.assertEquals(0, accounts.size(), 'Should not create an Account');
    }

    @IsTest
    static void testSyncGuardApplied() {
        Account acc = createTestAccount('cust_600', 'Guard Corp');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_600',
                'customer_name' => 'Guard Corp Updated',
                'old_customer_name' => 'Guard Corp',
                'license_type' => 'trial',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        System.assert(SyncGuard.inboundSyncIds.contains(acc.Id),
            'SyncGuard should contain the updated Account Id');
    }

    @IsTest
    static void testBulkEvents() {
        Account acc1 = createTestAccount('cust_bulk_1', 'Bulk One');
        Account acc2 = createTestAccount('cust_bulk_2', 'Bulk Two');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_bulk_1',
                'customer_name' => 'Bulk One Renamed',
                'old_customer_name' => 'Bulk One',
                'license_type' => 'paid',
                'old_license_type' => 'trial',
                'channel_changed' => true,
                'channel_name' => 'Beta',
                'expiration_changed' => false,
                'expires_at' => '2026-12-31T00:00:00Z'
            }),
            buildEvent(new Map<String, Object>{
                'customer_id' => 'cust_bulk_2',
                'customer_name' => 'Bulk Two',
                'old_customer_name' => 'Bulk Two',
                'license_type' => 'community',
                'old_license_type' => 'trial',
                'channel_changed' => false,
                'channel_name' => 'Stable',
                'expiration_changed' => true,
                'expires_at' => '2027-01-15T00:00:00Z'
            })
        };

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(events));
        Test.stopTest();

        Account updated1 = [SELECT Name, Replicated_License_Type__c, Replicated_Channel__c
                            FROM Account WHERE Id = :acc1.Id];
        System.assertEquals('Bulk One Renamed', updated1.Name);
        System.assertEquals('paid', updated1.Replicated_License_Type__c);
        System.assertEquals('Beta', updated1.Replicated_Channel__c);

        Account updated2 = [SELECT Name, Replicated_License_Type__c, Replicated_License_Expiry__c
                            FROM Account WHERE Id = :acc2.Id];
        System.assertEquals('Bulk Two', updated2.Name, 'Name should be unchanged');
        System.assertEquals('community', updated2.Replicated_License_Type__c);
        System.assertEquals(Date.valueOf('2027-01-15'), updated2.Replicated_License_Expiry__c);
    }

    @IsTest
    static void testMalformedPayloadSkipped() {
        Replicated_Webhook__e event = new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.CUSTOMER_UPDATED,
            Payload__c = 'not valid json'
        );

        Test.startTest();
        System.enqueueJob(new CustomerUpdatedHandler(new List<Replicated_Webhook__e>{ event }));
        Test.stopTest();

        // Should complete without exception.
        System.assert(true, 'Handler should not throw on malformed payload');
    }
}
