@IsTest
private class TrialSignupHandlerTest {

    private static String buildPayload(String customerName, String email) {
        Map<String, Object> data = new Map<String, Object>{
            'customer_name' => customerName,
            'email' => email
        };
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'Pending Self-Service Signup',
            'data' => data
        };
        return JSON.serialize(payload);
    }

    @IsTest
    static void testCreatesLead() {
        String payload = buildPayload('Acme Corp', 'trial@acme.com');

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(payload));
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

        String payload = buildPayload('Acme Corp', 'dup@acme.com');

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(payload));
        Test.stopTest();

        List<Lead> leads = [SELECT Id FROM Lead WHERE Email = 'dup@acme.com'];
        System.assertEquals(1, leads.size(), 'Should not create a duplicate Lead');
    }

    @IsTest
    static void testMissingCustomerNameUsesDefault() {
        String payload = buildPayload(null, 'noname@test.com');

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(payload));
        Test.stopTest();

        List<Lead> leads = [SELECT Id, LastName, Company FROM Lead WHERE Email = 'noname@test.com'];
        System.assertEquals(1, leads.size(), 'Should create a Lead even without customer name');
        System.assertEquals('Unknown', leads[0].LastName);
        System.assertEquals('Unknown', leads[0].Company);
    }

    @IsTest
    static void testNullEmailStillCreatesLead() {
        String payload = buildPayload('No Email Corp', null);

        Test.startTest();
        System.enqueueJob(new TrialSignupHandler(payload));
        Test.stopTest();

        List<Lead> leads = [SELECT Id, LastName FROM Lead WHERE Company = 'No Email Corp'];
        System.assertEquals(1, leads.size(), 'Should create a Lead even without email');
    }
}
