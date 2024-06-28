public class ReplicatedPlatform {

    private String apiToken { get; set; }

    public ReplicatedPlatform(ReplicatedVendorPortalCredential__mdt credential) {
        this.apiToken = credential.ApiToken__c;
    }

    private String parseLicenseId(String detailedCustomer) {
        JSONParser parser = JSON.createParser(detailedCustomer);
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

    public Boolean customerExists(OrderTerms terms) {
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
            String responseBody = res.getBody();
            System.debug('Response body: ' + responseBody);
            
            // Parse the JSON response
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            // Check the total_hits field
            if (responseMap.containsKey('total_hits')) {
                Integer totalHits = (Integer) responseMap.get('total_hits');
                if (totalHits == 0) {
                    return false;
                } else {
                    return true ;
                }
            } else {
                throw new ReplicatedAPIException('Error parsing response from Replicated API');
            }
        } else {
            System.debug('Error: ' + res.getStatus() + ' - ' + res.getStatusCode() + ' - ' + res.getBody());
            throw new ReplicatedAPIException('Error looking for existing Replicated customer ' + res.getStatus() + ' - ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }

    public String createLicense(OrderTerms terms) {
        Customer customer = new Customer(terms);
        System.debug('Creating license for customer: ' + customer.name);

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.replicated.com/vendor/v3/customer');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', this.apiToken);
        req.setBody(JSON.serialize(customer));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 201) {
            // Handle error
            System.debug('Error: ' + res.getStatusCode() + ' ' + res.getStatus());
            System.debug('Message: ' + res.getBody());
            return null;
        }

        return parseLicenseId(res.getBody());
    }

    public class Entitlement {
        public String name { get; set; }
        public String value { get; set; }
        public Boolean isDefault { get; set; }

        public Entitlement(String name, String value) {
            this.name = name;
            this.value = value;
            this.isDefault = false;
    }
    }

    public class Customer {
        public String name { get; set; }
        public String custom_id { get; set; }
        public String app_id { get; set; }
        public String channel_id { get; set; }
        public String email { get; set; }
        public List<Object> entitlementValues { get; set; } // Adjust type if specific type is known
        public String expires_at { get; set; }
        public Boolean is_airgap_enabled { get; set; }
        public Boolean is_geoaxis_supported { get; set; }
        public Boolean is_gitops_supported { get; set; }
        public Boolean is_embedded_cluster_download_enabled { get; set; }
        public Boolean is_identity_service_supported { get; set; }
        public Boolean is_kots_install_enabled { get; set; }
        public Boolean is_support_bundle_upload_enabled { get; set; }
        public Boolean is_snapshot_supported { get; set; }
        public Boolean is_disaster_recovery_supported { get; set; }
        public String type { get; set; }

        // Constructor
        public Customer(OrderTerms terms) {
            Time midnight = Time.newInstance(0,0,0,0);
            DateTime expirationDate = Datetime.newInstance(terms.endDate(), midnight) ;
            Integer userCount = terms.userCount();

            List<Entitlement> entitlements = new List<Entitlement>();
            entitlements.add(new Entitlement('member_count_max', String.ValueOf(userCount)));

            this.name = terms.customerName();
            this.custom_id = terms.accountId();
            this.app_id = terms.applicationId();
            this.channel_id = terms.channelId();
            this.email = terms.customerEmail();
            this.entitlementValues = entitlements; // Initialize as an empty list
            this.expires_at = (expirationDate != null) ? expirationDate.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
            this.is_geoaxis_supported = false;
            this.is_gitops_supported = false;
            this.is_identity_service_supported = false;
            this.type = 'prod';

            this.is_kots_install_enabled = terms.isAdminConsoleEnabled();
            this.is_embedded_cluster_download_enabled = terms.isEmbeddedClusterEnabled();
            this.is_airgap_enabled = terms.isAirgapEnabled();
            this.is_support_bundle_upload_enabled = terms.isSupportBundleUploadEnabled() ;
            this.is_snapshot_supported = terms.isSnapshotSupported() ;
            this.is_disaster_recovery_supported = terms.isDisasterRecoverySupported() ;
        }
    }

    public class ReplicatedAPIException extends Exception {}
}