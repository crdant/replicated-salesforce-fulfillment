@IsTest
private class EpUserJoinedHandlerTest {

    private static Replicated_Webhook__e buildEvent(
            String customerId, String customerName, String joinedEmail, Boolean isFirstUser) {
        Map<String, Object> data = new Map<String, Object>{
            'customer_id' => customerId,
            'customer_name' => customerName,
            'joined_email' => joinedEmail,
            'is_first_user' => isFirstUser
        };
        Map<String, Object> payload = new Map<String, Object>{
            'event' => ReplicatedEventType.CUSTOMER_EP_USER_JOINED,
            'data' => data
        };
        return new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.CUSTOMER_EP_USER_JOINED,
            Payload__c = JSON.serialize(payload)
        );
    }

    @IsTest
    static void testFirstUserConvertsLead() {
        Lead lead = new Lead(
            LastName = 'EP Corp',
            Company = 'EP Corp',
            Email = 'ep@corp.com',
            LeadSource = 'Self-Service Trial',
            Status = 'New',
            Replicated_Customer_Id__c = 'cust_ep',
            Replicated_License_Type__c = 'trial',
            Replicated_Channel__c = 'Stable',
            Replicated_License_Expiry__c = Date.valueOf('2026-06-15')
        );
        insert lead;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_ep', 'EP Corp', 'ep@corp.com', true)
        };

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(events));
        Test.stopTest();

        // Verify Lead was converted.
        Lead converted = [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :lead.Id];
        System.assert(converted.IsConverted, 'Lead should be converted');

        // Verify Account has all carried-over fields.
        Account acc = [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
                   Replicated_Channel__c, Replicated_License_Expiry__c
            FROM Account WHERE Id = :converted.ConvertedAccountId
        ];
        System.assertEquals('cust_ep', acc.Replicated_Customer_Id__c);
        System.assertEquals('trial', acc.Replicated_License_Type__c);
        System.assertEquals('Stable', acc.Replicated_Channel__c);
        System.assertEquals(Date.valueOf('2026-06-15'), acc.Replicated_License_Expiry__c);
    }

    @IsTest
    static void testFirstUserNoLeadCreatesAco() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_nolead', 'No Lead Corp', 'nolead@corp.com', true)
        };

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(events));
        Test.stopTest();

        List<Account> accounts = [
            SELECT Id, Name, Replicated_Customer_Id__c
            FROM Account WHERE Replicated_Customer_Id__c = 'cust_nolead'
        ];
        System.assertEquals(1, accounts.size(), 'Should create an Account directly');
        System.assertEquals('No Lead Corp', accounts[0].Name);

        List<Contact> contacts = [SELECT Id, Email FROM Contact WHERE AccountId = :accounts[0].Id];
        System.assertEquals(1, contacts.size(), 'Should create a Contact');
        System.assertEquals('nolead@corp.com', contacts[0].Email);

        List<Opportunity> opps = [SELECT Id, Name, StageName FROM Opportunity WHERE AccountId = :accounts[0].Id];
        System.assertEquals(1, opps.size(), 'Should create an Opportunity');
        System.assertEquals('Qualification', opps[0].StageName);
    }

    @IsTest
    static void testFirstUserAccountAlreadyExists() {
        Account existing = new Account(
            Name = 'Already Here',
            Replicated_Customer_Id__c = 'cust_exists'
        );
        insert existing;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_exists', 'Already Here', 'exists@corp.com', true)
        };

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(events));
        Test.stopTest();

        List<Account> accounts = [SELECT Id FROM Account WHERE Replicated_Customer_Id__c = 'cust_exists'];
        System.assertEquals(1, accounts.size(), 'Should not create a duplicate Account');
    }

    @IsTest
    static void testNotFirstUserSkipped() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_notfirst', 'Not First Corp', 'notfirst@corp.com', false)
        };

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(events));
        Test.stopTest();

        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(0, accounts.size(), 'Should not create records for non-first user');
    }

    @IsTest
    static void testLeadLookupFallsBackToEmail() {
        // Lead has no Replicated_Customer_Id__c — should be matched by email.
        Lead lead = new Lead(
            LastName = 'Email Match Corp',
            Company = 'Email Match Corp',
            Email = 'emailmatch@corp.com',
            LeadSource = 'Self-Service Trial',
            Status = 'New',
            Replicated_License_Type__c = 'trial',
            Replicated_Channel__c = 'Beta',
            Replicated_License_Expiry__c = Date.valueOf('2026-09-01')
        );
        insert lead;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_emailfb', 'Email Match Corp', 'emailmatch@corp.com', true)
        };

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(events));
        Test.stopTest();

        // Verify Lead was converted.
        Lead converted = [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :lead.Id];
        System.assert(converted.IsConverted, 'Lead should be converted via email fallback');

        // Verify Account has Replicated fields from the Lead.
        Account acc = [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
                   Replicated_Channel__c, Replicated_License_Expiry__c
            FROM Account WHERE Id = :converted.ConvertedAccountId
        ];
        System.assertEquals('cust_emailfb', acc.Replicated_Customer_Id__c);
        System.assertEquals('trial', acc.Replicated_License_Type__c);
        System.assertEquals('Beta', acc.Replicated_Channel__c);
        System.assertEquals(Date.valueOf('2026-09-01'), acc.Replicated_License_Expiry__c);
    }

    @IsTest
    static void testMalformedPayload() {
        Replicated_Webhook__e event = new Replicated_Webhook__e(
            Event_Type__c = ReplicatedEventType.CUSTOMER_EP_USER_JOINED,
            Payload__c = 'not valid json'
        );

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(new List<Replicated_Webhook__e>{ event }));
        Test.stopTest();

        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(0, accounts.size(), 'Should not create records from malformed payload');
    }

    @IsTest
    static void testBulkEvents() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(buildEvent(
                'cust_bulk_' + i,
                'Bulk Corp ' + i,
                'bulk' + i + '@corp.com',
                true
            ));
        }

        Test.startTest();
        System.enqueueJob(new EpUserJoinedHandler(events));
        Test.stopTest();

        // All 200 should create ACOs directly (no pre-existing Leads or Accounts).
        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(200, accounts.size(), 'Should create 200 Accounts');

        List<Contact> contacts = [SELECT Id FROM Contact];
        System.assertEquals(200, contacts.size(), 'Should create 200 Contacts');

        List<Opportunity> opps = [SELECT Id FROM Opportunity];
        System.assertEquals(200, opps.size(), 'Should create 200 Opportunities');
    }
}
