@IsTest
private class TrialSignupHandlerTest {

    private static Replicated_Webhook__e buildEvent(String customerName, String email) {
        Map<String, Object> data = new Map<String, Object>{
            'customer_name' => customerName,
            'email' => email
        };
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'customer.pending_signup',
            'data' => data
        };
        return new Replicated_Webhook__e(
            Event_Type__c = 'customer.pending_signup',
            Payload__c = JSON.serialize(payload)
        );
    }

    @IsTest
    static void testCreatesLead() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('Acme Corp', 'trial@acme.com')
        };

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(events));
        Test.stopTest();

        List<Lead> leads = [
            SELECT Id, LastName, Company, Email, LeadSource, Status
            FROM Lead WHERE Email = 'trial@acme.com'
        ];
        System.assertEquals(1, leads.size(), 'Should create exactly one Lead');
        System.assertEquals('Acme Corp', leads[0].LastName);
        System.assertEquals('Acme Corp', leads[0].Company);
        System.assertEquals('Self-Service Trial', leads[0].LeadSource);
        System.assertEquals('New', leads[0].Status);
    }

    @IsTest
    static void testDuplicateEmailSkipped() {
        // Pre-create a Lead with the same email
        insert new Lead(
            LastName = 'Existing',
            Company = 'Existing Co',
            Email = 'dup@acme.com',
            Status = 'New'
        );

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('Acme Corp', 'dup@acme.com')
        };

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(events));
        Test.stopTest();

        List<Lead> leads = [SELECT Id FROM Lead WHERE Email = 'dup@acme.com'];
        System.assertEquals(1, leads.size(), 'Should not create a duplicate Lead');
    }

    @IsTest
    static void testMissingCustomerNameUsesDefault() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent(null, 'noname@test.com')
        };

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(events));
        Test.stopTest();

        List<Lead> leads = [SELECT Id, LastName, Company FROM Lead WHERE Email = 'noname@test.com'];
        System.assertEquals(1, leads.size(), 'Should create a Lead even without customer name');
        System.assertEquals('Unknown', leads[0].LastName);
        System.assertEquals('Unknown', leads[0].Company);
    }

    @IsTest
    static void testBlankEmailSkipped() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('No Email Corp', null)
        };

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(events));
        Test.stopTest();

        List<Lead> leads = [SELECT Id FROM Lead WHERE Company = 'No Email Corp'];
        System.assertEquals(0, leads.size(), 'Should not create a Lead without email');
    }

    @IsTest
    static void testMalformedPayloadSkipped() {
        Replicated_Webhook__e event = new Replicated_Webhook__e(
            Event_Type__c = 'customer.pending_signup',
            Payload__c = 'not valid json'
        );

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(new List<Replicated_Webhook__e>{ event }));
        Test.stopTest();

        List<Lead> leads = [SELECT Id FROM Lead];
        System.assertEquals(0, leads.size(), 'Should not create a Lead from malformed payload');
    }

    @IsTest
    static void testBatchDeduplicatesWithinSameBatch() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('First Signup', 'batch@test.com'),
            buildEvent('Second Signup', 'batch@test.com')
        };

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(events));
        Test.stopTest();

        List<Lead> leads = [SELECT Id FROM Lead WHERE Email = 'batch@test.com'];
        System.assertEquals(1, leads.size(), 'Should deduplicate within the same batch');
    }
}
