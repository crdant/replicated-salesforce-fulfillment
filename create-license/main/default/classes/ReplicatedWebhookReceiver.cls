@RestResource(urlMapping='/replicated/webhook')
global class ReplicatedWebhookReceiver {

    private static final Integer MAX_PAYLOAD_LENGTH = 100000;

    @TestVisible
    private static String testSecret = null;

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String body = req.requestBody.toString();

        if (body.length() > MAX_PAYLOAD_LENGTH) {
            res.statusCode = 413;
            res.responseBody = Blob.valueOf('{"error":"Payload too large"}');
            return;
        }

        String signature = req.headers.get('X-Replicated-Signature');

        if (String.isBlank(signature)) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error":"Missing signature"}');
            return;
        }

        String secret = getWebhookSecret();
        if (secret == null) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error":"Server configuration error"}');
            return;
        }

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

    private static Boolean verifySignature(String body, String signature, String secret) {
        if (!signature.startsWith('sha256=')) {
            return false;
        }

        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(body),
            Blob.valueOf(secret)
        );
        String expected = 'sha256=' + EncodingUtil.convertToHex(mac);

        return constantTimeEquals(expected, signature);
    }

    private static Boolean constantTimeEquals(String a, String b) {
        if (a.length() != b.length()) {
            return false;
        }
        Integer result = 0;
        for (Integer i = 0; i < a.length(); i++) {
            result |= a.charAt(i) ^ b.charAt(i);
        }
        return result == 0;
    }

    @TestVisible
    private static String getWebhookSecret() {
        if (testSecret != null) {
            return testSecret;
        }
        List<Replicated_Webhook_Secret__mdt> secrets = [
            SELECT Secret__c
            FROM Replicated_Webhook_Secret__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (secrets.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Webhook secret not configured: no Replicated_Webhook_Secret__mdt record with DeveloperName=Default');
            return null;
        }
        return secrets[0].Secret__c;
    }
}
