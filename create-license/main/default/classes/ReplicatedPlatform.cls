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

        System.debug('License ID: ' + licenseId);
        return licenseId ;
    }

    public String createLicense(Contract contract) {
        Customer customer = new Customer(new Application('2Ukd6bgLamUYOegqsNOPfjpfQVC'), contract);
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

        System.debug('parsing reponse for the license id');
        return parseLicenseId(res.getBody()); 
    }

    public class Application {
        public String id { get; set; }

        public Application(String id) {
            this.id = id;
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
        public Boolean is_helmvm_download_enabled { get; set; }
        public Boolean is_identity_service_supported { get; set; }
        public Boolean is_kots_install_enabled { get; set; }
        public Boolean is_snapshot_supported { get; set; }
        public Boolean is_support_bundle_upload_enabled { get; set; }
        public String type { get; set; }

        // Constructor
        public Customer(Application app, Contract contract) {
            Account account = [ SELECT Id, Name FROM Account WHERE Id = :contract.AccountId LIMIT 1 ];
            Time midnight = Time.newInstance(0,0,0,0);
            DateTime expirationDate = (contract.EndDate != null) ? Datetime.newInstance(contract.EndDate, midnight) : null;

            this.name = account.Name;
            this.custom_id = account.Id;
            this.app_id = app.id;
            this.channel_id = '2Ukd6ZSK5i9We0m9WznyBI19RtM';
            this.email = 'test@example.com';
            this.entitlementValues = new List<Object>(); // Initialize as an empty list
            this.expires_at = ( expirationDate != null ) ? expirationDate.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
            this.is_airgap_enabled = contract.IsAirgapEnabled__c;
            this.is_geoaxis_supported = false;
            this.is_gitops_supported = false;
            this.is_helmvm_download_enabled = contract.IsEmbeddedClusterEnabled__c;
            this.is_identity_service_supported = false;
            this.is_kots_install_enabled = contract.IsAdminConsoleEnabled__c;
            this.is_snapshot_supported = contract.IsSnapshotSupported__c;
            this.is_support_bundle_upload_enabled = contract.IsSupportBundleUploadEnabled__c;
            this.type = 'prod';
        }
    }

}
