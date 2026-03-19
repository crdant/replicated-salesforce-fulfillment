@IsTest
private class AssetDownloadedHandlerTest {

    private static Replicated_Webhook__e buildEvent(Map<String, Object> data) {
        Map<String, Object> payload = new Map<String, Object>{
            'event' => ReplicatedEventType.RELEASE_ASSET_DOWNLOADED,
            'data' => data
        };
        return new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.RELEASE_ASSET_DOWNLOADED,
            Payload__c = JSON.serialize(payload)
        );
    }

    private static Map<String, Object> buildDownloadData(
            String customerId, String licenseType, String appId, String appName) {
        return new Map<String, Object>{
            'customer_id' => customerId,
            'customer_name' => 'Test Customer',
            'license_type' => licenseType,
            'app_id' => appId,
            'app_name' => appName,
            'asset_type' => 'helm_chart',
            'asset_name' => 'slackernews',
            'asset_version' => '1.0.0',
            'channel_name' => 'Stable',
            'downloaded_at' => '2026-03-19T14:30:00Z'
        };
    }

    private static Account createTestAccount(String customerId, String name) {
        Account acc = new Account(
            Name = name,
            Replicated_Customer_Id__c = customerId
        );
        insert acc;
        return acc;
    }

    // Creates a full Order chain: Product2 → PricebookEntry → Opportunity →
    // OpportunityLineItem → Order with LicenseId__c.
    private static Order createOrderWithProduct(Account acc, String appId, String licenseId) {
        Product2 product = new Product2(
            Name = 'Test Product',
            Application__c = appId,
            IsActive = true,
            IsAddOn__c = false
        );
        insert product;

        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = product.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            Name = acc.Name + ' - Deal',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Pricebook2Id = stdPricebookId
        );
        insert opp;

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 1000
        );
        insert oli;

        Order ord = new Order(
            AccountId = acc.Id,
            OpportunityId = opp.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPricebookId,
            LicenseId__c = licenseId
        );
        insert ord;
        return ord;
    }

    @IsTest
    static void testTrialDownloadCreatesRecord() {
        Account acc = createTestAccount('cust_trial', 'Trial Corp');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(buildDownloadData('cust_trial', 'trial', 'app_123', 'SlackerNews'))
        };

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        List<Replicated_Download__c> downloads = [
            SELECT Account__c, Asset_Type__c, Asset_Name__c, Asset_Version__c,
                   Channel_Name__c, License_Type__c, Downloaded_At__c,
                   Replicated_Customer_Id__c, App_Name__c
            FROM Replicated_Download__c
            WHERE Account__c = :acc.Id
        ];
        System.assertEquals(1, downloads.size(), 'Should create one download record');

        Replicated_Download__c dl = downloads[0];
        System.assertEquals('helm_chart', dl.Asset_Type__c);
        System.assertEquals('slackernews', dl.Asset_Name__c);
        System.assertEquals('1.0.0', dl.Asset_Version__c);
        System.assertEquals('Stable', dl.Channel_Name__c);
        System.assertEquals('trial', dl.License_Type__c);
        System.assertEquals('cust_trial', dl.Replicated_Customer_Id__c);
        System.assertEquals('SlackerNews', dl.App_Name__c);
        System.assertNotEquals(null, dl.Downloaded_At__c);
    }

    @IsTest
    static void testPaidDownloadFulfillsOrder() {
        Account acc = createTestAccount('cust_paid', 'Paid Corp');
        Order ord = createOrderWithProduct(acc, 'app_paid', 'lic_001');

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(buildDownloadData('cust_paid', 'paid', 'app_paid', 'SlackerNews'))
        };

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        // Download record created.
        List<Replicated_Download__c> downloads = [
            SELECT Id FROM Replicated_Download__c WHERE Account__c = :acc.Id
        ];
        System.assertEquals(1, downloads.size(), 'Should create download record');

        // Order fulfilled.
        Order updated = [SELECT FulfilledAt__c FROM Order WHERE Id = :ord.Id];
        System.assertNotEquals(null, updated.FulfilledAt__c, 'FulfilledAt__c should be set');

        // SyncGuard applied.
        System.assert(SyncGuard.inboundSyncIds.contains(ord.Id),
            'SyncGuard should contain the fulfilled Order Id');
    }

    @IsTest
    static void testPaidDownloadOrderAlreadyFulfilled() {
        Account acc = createTestAccount('cust_already', 'Already Corp');
        Order ord = createOrderWithProduct(acc, 'app_already', 'lic_002');

        // Pre-set FulfilledAt__c.
        ord.FulfilledAt__c = DateTime.newInstance(2026, 1, 1, 0, 0, 0);
        update ord;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(buildDownloadData('cust_already', 'paid', 'app_already', 'SlackerNews'))
        };

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        // Download still created.
        List<Replicated_Download__c> downloads = [
            SELECT Id FROM Replicated_Download__c WHERE Account__c = :acc.Id
        ];
        System.assertEquals(1, downloads.size(), 'Should still create download record');

        // FulfilledAt__c unchanged (original value preserved).
        Order unchanged = [SELECT FulfilledAt__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(
            DateTime.newInstance(2026, 1, 1, 0, 0, 0),
            unchanged.FulfilledAt__c,
            'FulfilledAt__c should remain unchanged'
        );
    }

    @IsTest
    static void testPaidDownloadNoOrder() {
        Account acc = createTestAccount('cust_noorder', 'No Order Corp');
        // No Order created for this Account.

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(buildDownloadData('cust_noorder', 'paid', 'app_noorder', 'SlackerNews'))
        };

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        // Download still created even though no Order to fulfill.
        List<Replicated_Download__c> downloads = [
            SELECT Id FROM Replicated_Download__c WHERE Account__c = :acc.Id
        ];
        System.assertEquals(1, downloads.size(), 'Should create download record regardless of Order');
    }

    @IsTest
    static void testNoAccountSkips() {
        // No Account exists for this customer_id.
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(buildDownloadData('cust_unknown', 'trial', 'app_123', 'SlackerNews'))
        };

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        List<Replicated_Download__c> downloads = [SELECT Id FROM Replicated_Download__c];
        System.assertEquals(0, downloads.size(), 'Should not create records when no Account found');
    }

    @IsTest
    static void testMalformedPayload() {
        Replicated_Webhook__e event = new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.RELEASE_ASSET_DOWNLOADED,
            Payload__c = 'not valid json'
        );

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(new List<Replicated_Webhook__e>{ event }));
        Test.stopTest();

        List<Replicated_Download__c> downloads = [SELECT Id FROM Replicated_Download__c];
        System.assertEquals(0, downloads.size(), 'Should not create records from malformed payload');
    }

    @IsTest
    static void testBulkDownloads() {
        // Create 200 Accounts with downloads.
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(
                Name = 'Bulk Corp ' + i,
                Replicated_Customer_Id__c = 'cust_bulk_' + i
            ));
        }
        insert accounts;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(buildEvent(buildDownloadData(
                'cust_bulk_' + i, 'trial', 'app_bulk', 'BulkApp'
            )));
        }

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        Integer downloadCount = [SELECT COUNT() FROM Replicated_Download__c];
        System.assertEquals(200, downloadCount, 'Should create 200 download records');
    }

    @IsTest
    static void testMultipleOrdersMatchesCorrectApp() {
        Account acc = createTestAccount('cust_multi', 'Multi App Corp');

        // Create two Orders for different apps on the same Account.
        Order orderAppA = createOrderWithProduct(acc, 'app_aaa', 'lic_aaa');
        Order orderAppB = createOrderWithProduct(acc, 'app_bbb', 'lic_bbb');

        // Download for app_bbb — should fulfill orderAppB, not orderAppA.
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(buildDownloadData('cust_multi', 'paid', 'app_bbb', 'AppB'))
        };

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(events));
        Test.stopTest();

        Order updatedA = [SELECT FulfilledAt__c FROM Order WHERE Id = :orderAppA.Id];
        System.assertEquals(null, updatedA.FulfilledAt__c,
            'Order for app_aaa should NOT be fulfilled');

        Order updatedB = [SELECT FulfilledAt__c FROM Order WHERE Id = :orderAppB.Id];
        System.assertNotEquals(null, updatedB.FulfilledAt__c,
            'Order for app_bbb should be fulfilled');
    }
}
