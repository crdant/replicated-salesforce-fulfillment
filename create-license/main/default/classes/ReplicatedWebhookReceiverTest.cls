@IsTest
private class ReplicatedWebhookReceiverTest {

    private static final String TEST_SECRET = 'test-webhook-secret-key';

    private static void setupTestSecret() {
        ReplicatedWebhookReceiver.testSecret = TEST_SECRET;
    }

    private static String generateSignature(String body) {
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(body),
            Blob.valueOf(TEST_SECRET)
        );
        return 'sha256=' + EncodingUtil.convertToHex(mac);
    }

    private static String validPayload(String eventType) {
        return '{"event":"' + eventType + '","timestamp":"2026-01-25T22:48:32Z",' +
            '"text":"Test event","data":{"app_id":"app123","customer_id":"cust456",' +
            '"customer_name":"Test Customer"}}';
    }

    private static RestRequest buildRequest(String body, String signature) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/replicated/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        if (signature != null) {
            req.headers.put('X-Replicated-Signature', signature);
        }
        return req;
    }

    @IsTest
    static void testValidSignature() {
        setupTestSecret();
        String body = validPayload('customer.created');

        RestContext.request = buildRequest(body, generateSignature(body));
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Valid signature should return 200');
    }

    @IsTest
    static void testInvalidSignature() {
        setupTestSecret();
        String body = validPayload('customer.created');

        RestContext.request = buildRequest(body, 'sha256=invalid');
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Invalid signature should return 401');
    }

    @IsTest
    static void testMissingSignature() {
        setupTestSecret();
        String body = validPayload('customer.created');

        RestContext.request = buildRequest(body, null);
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Missing signature should return 401');
    }

    @IsTest
    static void testMalformedJson() {
        setupTestSecret();
        String body = 'not valid json{{{';

        RestContext.request = buildRequest(body, generateSignature(body));
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Malformed JSON should return 400');
    }

    @IsTest
    static void testMissingEventType() {
        setupTestSecret();
        String body = '{"data":{"customer_id":"cust456"}}';

        RestContext.request = buildRequest(body, generateSignature(body));
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Missing event type should return 400');
    }

    @IsTest
    static void testCustomerCreatedEvent() {
        setupTestSecret();
        String body = validPayload('customer.created');

        RestContext.request = buildRequest(body, generateSignature(body));
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void testInstanceCreatedEvent() {
        setupTestSecret();
        String body = validPayload('instance.created');

        RestContext.request = buildRequest(body, generateSignature(body));
        RestContext.response = new RestResponse();

        Test.startTest();
        ReplicatedWebhookReceiver.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void testVerifySignatureDirectly() {
        String body = '{"test":"data"}';
        String signature = generateSignature(body);

        System.assert(
            ReplicatedWebhookReceiver.verifySignature(body, signature, TEST_SECRET),
            'Matching signature should verify'
        );
        System.assert(
            !ReplicatedWebhookReceiver.verifySignature(body, 'sha256=wrong', TEST_SECRET),
            'Wrong signature should not verify'
        );
    }
}
