public class ReplicatedPlatform {

    private String apiToken { get; set; }

    public ReplicatedPlatform(ReplicatedVendorPortalCredential__mdt credential) {
        this.apiToken = credential.ApiToken__c;
    }

    private String parseLicenseId(String detailedReplicatedCustomer) {
        JSONParser parser = JSON.createParser(detailedReplicatedCustomer);
        String licenseId = '';

        while (parser.nextToken() != null) {
            if (parser.getCurrentToken() == JSONToken.FIELD_NAME) {
                String fieldName = parser.getText();
                parser.nextToken();
                if (fieldName == 'customer') {
                    while (parser.nextToken() != JSONToken.END_OBJECT) {
                        if ((parser.getCurrentToken() == JSONToken.FIELD_NAME) && (parser.getText() == 'installationId')) {
                            parser.nextToken();
                            licenseId = parser.getText();
                            break;
                        }
                    }
                }
            }
        }

        return licenseId;
    }

    public ReplicatedApplication loadApplication(String appId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + appId);
        req.setMethod('GET');
        req.setHeader('accept', 'application/json');
        req.setHeader('Authorization', this.apiToken);

        Http http = new Http();
        HttpResponse res = http.send(req);

        
        Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (resultMap.containsKey('app')) {
            ReplicatedApplication application = (ReplicatedApplication) JSON.deserialize(JSON.serialize(resultMap.get('app')), ReplicatedApplication.class);
            return application;
        }
        return null;
    }

    public String platformHostname(String kind, String appId, String channelId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + appId + '/channel/' + channelId);
        req.setMethod('GET');
        req.setHeader('accept', 'application/json');
        req.setHeader('Authorization', this.apiToken);

        Http http = new Http();
        HttpResponse res = http.send(req);

        
        Map<String, Object> channelResultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> channel = (Map<String, Object>) channelResultMap.get('channel');
        Map<String, Object> overrides = (Map<String, Object>) channel.get('customHostnameOverrides');
        if (overrides.containsKey(kind)) {
            Map<String, Object> entry = (Map<String, Object>) overrides.get(kind);
            if ((String)entry.get('hostname') != '') {
                System.debug('providing hostname' + (String)entry.get('hostname'));
                return (String)entry.get('hostname');
            }
        }

        System.debug('no override on the channel');

        req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + appId + '/custom-hostnames');
        req.setMethod('GET');
        req.setHeader('accept', 'application/json');
        req.setHeader('Authorization', this.apiToken);

        http = new Http();
        res = http.send(req);
        System.debug('body: ' + res.getBody());
        
        Map<String, Object> hostnameResultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> appCustomHostnames = (List<Object>) hostnameResultMap.get(kind);
        for (Object hostnameEntry : (List<Object>) hostnameResultMap.get(kind)) {
            Map<String, Object> hostname = (Map<String, Object>) hostnameEntry;
            if ((Boolean) hostname.get('is_default') == true) {
                System.debug('providing hostname' + (String)hostname.get('hostname'));
                return (String)hostname.get('hostname');
            }
        }

        System.debug('no custom hostname');

        switch on kind {
            when 'registry' {
                return 'registry.replicated.com';
            }
            when 'proxy' {
                return 'proxy.replicated.com';
            }
            when 'replicatedApp' {
                return 'replicated.app';
            }
            when 'downloadPortal' {
                return 'get.replicated.com';
            }
        }
        return null ;
    } 

    public ReplicatedApplication loadApplication(ReplicatedCustomer customer) {
        return loadApplication(customer.appId);
    } 

    public ReplicatedChannel loadChannel(String appId, String channelId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + appId + '/channel/' + channelId);
        req.setMethod('GET');
        req.setHeader('accept', 'application/json');
        req.setHeader('Authorization', this.apiToken);

        Http http = new Http();
        HttpResponse res = http.send(req);

        
        Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (resultMap.containsKey('channel')) {
            ReplicatedChannel channel = (ReplicatedChannel) JSON.deserialize(JSON.serialize(resultMap.get('channel')), ReplicatedChannel.class);
            return channel;
        }
        return null;
    }

    public ReplicatedChannel loadChannel(ReplicatedCustomer customer) {
        return loadChannel(customer.appId, customer.channelId);
    } 

    public ReplicatedCustomer loadCustomer(LicenseTerms terms) {
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

    public String getLicenseFile(LicenseTerms terms) {
        ReplicatedCustomer customer = this.loadCustomer(terms);
        if (customer == null) {
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/app/' + terms.applicationId() + '/customer/' + customer.id + '/license-download');
        req.setMethod('GET');
        req.setHeader('Authorization', this.apiToken);

        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug('license: ' + res.getBody());
        return res.getBody();
    }

    public Boolean customerExists(LicenseTerms terms) {
        ReplicatedCustomer customer = this.loadCustomer(terms);
        return ( customer != null ) ;
    }

    public String createLicense(LicenseTerms terms) {
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
            System.debug('Message: ' + res.getBody());
            return null;
        } else {
            Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String customerJson = JSON.serialize(resultMap.get('customer'));
            ReplicatedCustomer created = ReplicatedCustomer.create(customerJson);
            return created.licenseId ;
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
            System.debug('Message: ' + res.getBody());
        } else {
            Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String customerJson = JSON.serialize(resultMap.get('customer'));
            ReplicatedCustomer created = ReplicatedCustomer.create(customerJson);
        }

    }

    public class ReplicatedAPIException extends Exception {}
}
