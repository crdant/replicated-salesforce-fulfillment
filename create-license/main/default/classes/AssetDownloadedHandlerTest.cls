@IsTest
private class AssetDownloadedHandlerTest {

    private static String buildPayload(String customerId, String customerName, String email) {
        Map<String, Object> data = new Map<String, Object>{
            'customer_id' => customerId,
            'customer_name' => customerName,
            'email' => email
        };
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'Release Assets Downloaded',
            'data' => data
        };
        return JSON.serialize(payload);
    }

    @IsTest
    static void testConvertsLeadToAccountContactOpportunity() {
        Lead lead = new Lead(
            LastName = 'Trial Corp',
            Company = 'Trial Corp',
            Email = 'trial@corp.com',
            LeadSource = 'Self-Service Trial',
            Status = 'New',
            Replicated_Customer_Id__c = 'cust_conv',
            Replicated_License_Type__c = 'trial',
            Replicated_Channel__c = 'Stable'
        );
        insert lead;

        String payload = buildPayload('cust_conv', 'Trial Corp', 'trial@corp.com');

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(payload));
        Test.stopTest();

        // Verify Lead was converted
        Lead converted = [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :lead.Id];
        System.assert(converted.IsConverted, 'Lead should be converted');

        // Verify Account has Replicated_Customer_Id__c
        Account acc = [SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c, Replicated_Channel__c
                       FROM Account WHERE Id = :converted.ConvertedAccountId];
        System.assertEquals('cust_conv', acc.Replicated_Customer_Id__c);
        System.assertEquals('trial', acc.Replicated_License_Type__c);
        System.assertEquals('Stable', acc.Replicated_Channel__c);
    }

    @IsTest
    static void testIdempotentSkipsWhenAccountExists() {
        Account existing = new Account(
            Name = 'Already Here',
            Replicated_Customer_Id__c = 'cust_exists'
        );
        insert existing;

        String payload = buildPayload('cust_exists', 'Already Here', 'exists@corp.com');

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(payload));
        Test.stopTest();

        // Should still have only one Account
        List<Account> accounts = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = 'cust_exists'];
        System.assertEquals(1, accounts.size(), 'Should not create a duplicate Account');
    }

    @IsTest
    static void testCreatesDirectlyWhenNoLead() {
        String payload = buildPayload('cust_direct', 'Direct Corp', 'direct@corp.com');

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(payload));
        Test.stopTest();

        List<Account> accounts = [
            SELECT Id, Name, Replicated_Customer_Id__c
            FROM Account WHERE Replicated_Customer_Id__c = 'cust_direct'
        ];
        System.assertEquals(1, accounts.size(), 'Should create an Account directly');
        System.assertEquals('Direct Corp', accounts[0].Name);

        List<Contact> contacts = [SELECT Id, Email FROM Contact WHERE AccountId = :accounts[0].Id];
        System.assertEquals(1, contacts.size(), 'Should create a Contact');
        System.assertEquals('direct@corp.com', contacts[0].Email);

        List<Opportunity> opps = [SELECT Id, Name, StageName FROM Opportunity WHERE AccountId = :accounts[0].Id];
        System.assertEquals(1, opps.size(), 'Should create an Opportunity');
        System.assertEquals('Qualification', opps[0].StageName);
    }

    @IsTest
    static void testDuplicateEventAfterConversion() {
        // Simulate a Lead that was already converted and an Account that already exists
        Lead lead = new Lead(
            LastName = 'Dup Event Corp',
            Company = 'Dup Event Corp',
            Email = 'dup@event.com',
            Status = 'New',
            Replicated_Customer_Id__c = 'cust_dup'
        );
        insert lead;

        // Convert the Lead manually to simulate prior handler execution
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        LeadStatus convertedStatus = [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true LIMIT 1
        ];
        lc.setConvertedStatus(convertedStatus.MasterLabel);
        Database.LeadConvertResult lcr = Database.convertLead(lc);

        // Set Replicated_Customer_Id__c on the Account
        Account acc = [SELECT Id FROM Account WHERE Id = :lcr.getAccountId()];
        acc.Replicated_Customer_Id__c = 'cust_dup';
        update acc;

        String payload = buildPayload('cust_dup', 'Dup Event Corp', 'dup@event.com');

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(payload));
        Test.stopTest();

        // Should still have only one Account -- the handler skipped because Account exists
        List<Account> accounts = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = 'cust_dup'];
        System.assertEquals(1, accounts.size(), 'Duplicate event should not create another Account');
    }

    @IsTest
    static void testMissingCustomerNameUsesDefault() {
        String payload = buildPayload('cust_noname', null, 'noname@test.com');

        Test.startTest();
        System.enqueueJob(new AssetDownloadedHandler(payload));
        Test.stopTest();

        List<Account> accounts = [
            SELECT Id, Name FROM Account WHERE Replicated_Customer_Id__c = 'cust_noname'
        ];
        System.assertEquals(1, accounts.size(), 'Should create Account with default name');
        System.assertEquals('Unknown', accounts[0].Name);
    }
}
