public class ReplicatedPlatform {

    private String apiToken { get; set; }

    public ReplicatedPlatform(ReplicatedVendorPortalCredential__mdt credential) {
        this.apiToken = credential.ApiToken__c;
    }

    public ReplicatedCustomer loadCustomer(OrderTerms terms) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/customers/search');
        req.setMethod('POST');
        req.setHeader('accept', 'application/json');
        req.setHeader('content-type', 'application/json');
        req.setHeader('Authorization', this.apiToken);
        
        String query = 'customId:' + terms.accountId();
        String requestBody = '{"app_id":"' + terms.applicationId() + '","query":"' + query + '","include_paid":true,"include_active":true,"include_inactive":true}';
        req.setBody(requestBody);
        
        Http http = new Http();
        HttpResponse res = http.send(req);

        
        if (res.getStatusCode() == 200) {
            // Parse the JSON response
            Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (resultMap.containsKey('total_hits')) {
                Integer totalHits = (Integer) resultMap.get('total_hits');
                if (totalHits == 0) {
                    return null;
                } else {
                    List<Object> customers = (List<Object>) resultMap.get('customers');
                    String customerJson = JSON.serialize(customers[0]);
                    return ReplicatedCustomer.create(customerJson);
                }
            }
            throw new ReplicatedAPIException('Error parsing response from Replicated API');
        } 
        return null ;
    }

    public ReplicatedCustomer createLicense(OrderTerms terms) {
        ReplicatedCustomer customer = new ReplicatedCustomer(terms);
        System.debug('Creating license for customer: ' + customer.name);

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/customer');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', this.apiToken);
        req.setBody(customer.createRequest());
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 201) {
            // Handle error
            System.debug('Error: ' + res.getStatusCode() + ' ' + res.getStatus());
            return null;
        } else {
            Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String customerJson = JSON.serialize(resultMap.get('customer'));
            ReplicatedCustomer created = ReplicatedCustomer.create(customerJson);
            return created;
        }

    }

    public void updateCustomer(ReplicatedCustomer customer) {
        System.debug('Updating license for customer: ' + customer.name);

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/customer');
        req.setMethod('PUT');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', this.apiToken);
        req.setBody(customer.createRequest());
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 201) {
            // Handle error
            System.debug('Error: ' + res.getStatusCode() + ' ' + res.getStatus());
        } else {
            Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String customerJson = JSON.serialize(resultMap.get('customer'));
            ReplicatedCustomer created = ReplicatedCustomer.create(customerJson);
        }

    }

    public String getLicenseFile(String appId, String customerId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + appId + '/customer/' + customerId + '/license-download');
        req.setMethod('GET');
        req.setHeader('Authorization', this.apiToken);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            System.debug('Error downloading license: ' + res.getStatusCode() + ' ' + res.getStatus());
            return null;
        }
        return res.getBody();
    }

    public void inviteToPortal(String appId, String customerId, String email) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + appId + '/enterprise-portal/customer-user');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', this.apiToken);

        Map<String, String> body = new Map<String, String>();
        body.put('customer_id', customerId);
        body.put('email_address', email);
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new ReplicatedAPIException(
                'Failed to invite user to Enterprise Portal. Status: ' + res.getStatusCode()
                + ' ' + res.getStatus()
            );
        }
    }

    public class ReplicatedAPIException extends Exception {}
}
