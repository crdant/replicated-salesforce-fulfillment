@IsTest
private class CustomerCreatedHandlerTest {

    private static Replicated_Webhook__e buildEvent(String customerId, String customerName,
            String email, String licenseType, String expiresAt, String channelName) {
        Map<String, Object> data = new Map<String, Object>{
            'customer_id' => customerId,
            'customer_name' => customerName,
            'email' => email,
            'license_type' => licenseType,
            'expires_at' => expiresAt,
            'channel_name' => channelName
        };
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'customer.created',
            'data' => data
        };
        return new Replicated_Webhook__e(
            Event_Type__c = 'customer.created',
            Payload__c = JSON.serialize(payload)
        );
    }

    @IsTest
    static void testEnrichesExistingLead() {
        Lead existingLead = new Lead(
            LastName = 'Acme Corp',
            Company = 'Acme Corp',
            Email = 'user@acme.com',
            LeadSource = 'Self-Service Trial',
            Status = 'New'
        );
        insert existingLead;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_123', 'Acme Corp', 'user@acme.com',
                'trial', '2026-06-15T00:00:00Z', 'Stable')
        };

        Test.startTest();
        System.enqueueJob(new CustomerCreatedHandler(events));
        Test.stopTest();

        Lead updated = [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Type__c,
                   Replicated_Channel__c, Replicated_License_Expiry__c
            FROM Lead WHERE Id = :existingLead.Id
        ];
        System.assertEquals('cust_123', updated.Replicated_Customer_Id__c);
        System.assertEquals('trial', updated.Replicated_License_Type__c);
        System.assertEquals('Stable', updated.Replicated_Channel__c);
        System.assertEquals(Date.valueOf('2026-06-15'), updated.Replicated_License_Expiry__c);
    }

    @IsTest
    static void testCreatesLeadWhenNoneExists() {
        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_456', 'New Corp', 'new@corp.com',
                'trial', '2026-12-31T00:00:00Z', 'Beta')
        };

        Test.startTest();
        System.enqueueJob(new CustomerCreatedHandler(events));
        Test.stopTest();

        List<Lead> leads = [
            SELECT Id, LastName, Company, Email, Replicated_Customer_Id__c,
                   Replicated_License_Type__c, Replicated_Channel__c,
                   Replicated_License_Expiry__c, LeadSource
            FROM Lead WHERE Email = 'new@corp.com'
        ];
        System.assertEquals(1, leads.size(), 'Should create a new Lead');
        System.assertEquals('New Corp', leads[0].LastName);
        System.assertEquals('cust_456', leads[0].Replicated_Customer_Id__c);
        System.assertEquals('trial', leads[0].Replicated_License_Type__c);
        System.assertEquals('Beta', leads[0].Replicated_Channel__c);
        System.assertEquals('Self-Service Trial', leads[0].LeadSource);
    }

    @IsTest
    static void testSkipsConvertedLead() {
        // Create and convert a Lead so there is no unconverted match
        Lead existingLead = new Lead(
            LastName = 'Converted Corp',
            Company = 'Converted Corp',
            Email = 'converted@corp.com',
            Status = 'New'
        );
        insert existingLead;

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(existingLead.Id);
        LeadStatus convertedStatus = [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true LIMIT 1
        ];
        lc.setConvertedStatus(convertedStatus.MasterLabel);
        Database.convertLead(lc);

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_789', 'Converted Corp', 'converted@corp.com',
                'trial', '2026-06-15T00:00:00Z', 'Stable')
        };

        Test.startTest();
        System.enqueueJob(new CustomerCreatedHandler(events));
        Test.stopTest();

        // Should create a new Lead since the existing one is converted
        List<Lead> leads = [
            SELECT Id FROM Lead
            WHERE Email = 'converted@corp.com' AND IsConverted = false
        ];
        System.assertEquals(1, leads.size(), 'Should create a new Lead when existing is converted');
    }

    @IsTest
    static void testHandlesNullExpiry() {
        Lead existingLead = new Lead(
            LastName = 'No Expiry',
            Company = 'No Expiry',
            Email = 'noexpiry@test.com',
            Status = 'New'
        );
        insert existingLead;

        List<Replicated_Webhook__e> events = new List<Replicated_Webhook__e>{
            buildEvent('cust_noexp', 'No Expiry', 'noexpiry@test.com',
                'community', null, 'Stable')
        };

        Test.startTest();
        System.enqueueJob(new CustomerCreatedHandler(events));
        Test.stopTest();

        Lead updated = [
            SELECT Id, Replicated_Customer_Id__c, Replicated_License_Expiry__c
            FROM Lead WHERE Id = :existingLead.Id
        ];
        System.assertEquals('cust_noexp', updated.Replicated_Customer_Id__c);
        System.assertEquals(null, updated.Replicated_License_Expiry__c);
    }
}
