@RestResource(urlMapping='/replicated/webhook')
global class ReplicatedWebhookReceiver {

    @TestVisible
    private static String testSecret = null;

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody.toString();
        String signature = req.headers.get('X-Replicated-Signature');

        if (String.isBlank(signature)) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error":"Missing signature"}');
            return;
        }

        String secret = getWebhookSecret();
        if (!verifySignature(body, signature, secret)) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error":"Invalid signature"}');
            return;
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"error":"Malformed JSON"}');
            return;
        }

        String eventType = (String) payload.get('event');
        Map<String, Object> data = (Map<String, Object>) payload.get('data');
        String customerId = (data != null) ? (String) data.get('customer_id') : null;

        if (String.isBlank(eventType)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"error":"Missing event type"}');
            return;
        }

        Replicated_Webhook__e event = new Replicated_Webhook__e(
            Event_Type__c = eventType,
            Payload__c = body,
            Customer_Id__c = String.isNotBlank(customerId) ? customerId : ''
        );

        Database.SaveResult sr = EventBus.publish(event);
        if (!sr.isSuccess()) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error":"Failed to publish event"}');
            return;
        }

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('{"status":"ok"}');
    }

    @TestVisible
    private static Boolean verifySignature(String body, String signature, String secret) {
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(body),
            Blob.valueOf(secret)
        );
        String expected = 'sha256=' + EncodingUtil.convertToHex(mac);
        return expected.equals(signature);
    }

    @TestVisible
    private static String getWebhookSecret() {
        if (testSecret != null) {
            return testSecret;
        }
        Replicated_Webhook_Secret__mdt secretRecord = [
            SELECT Secret__c
            FROM Replicated_Webhook_Secret__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return secretRecord.Secret__c;
    }
}
