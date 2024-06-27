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
        return licenseId;
    }

    public String createLicense(Order order) {
        Product2 coreProduct = [SELECT Product2.ProductCode, Product2.Application__c, Product2.ReleaseChannel__c 
                                FROM Product2
                                WHERE Id IN (SELECT Product2Id FROM OrderItem WHERE OrderId = :order.Id)
                                  AND Product2.ProductCode <> 'slackernews-users' 
                                LIMIT 1];
        
        Application app = new Application(coreProduct.Application__c, coreProduct.ReleaseChannel__c, coreProduct.ProductCode);
        Customer customer = new Customer(app, order);
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

        System.debug('Parsing response for the license id');
        return parseLicenseId(res.getBody());
    }

    public class Application {
        public String id { get; set; }
        public String channel { get; set; }
        public String productCode { get; set; }

        public Application(String id, String channel, String productCode) {
            this.id = id;
            this.channel = channel;
            this.productCode = productCode;
        }
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
        public Boolean is_helmvm_download_enabled { get; set; }
        public Boolean is_identity_service_supported { get; set; }
        public Boolean is_kots_install_enabled { get; set; }
        public Boolean is_snapshot_supported { get; set; }
        public Boolean is_support_bundle_upload_enabled { get; set; }
        public String type { get; set; }

        // Constructor
        public Customer(Application app, Order order) {
            Account account = [SELECT Id, Name FROM Account WHERE Id = :order.AccountId LIMIT 1];
            Time midnight = Time.newInstance(0,0,0,0);
            DateTime expirationDate = (order.EndDate != null) ? Datetime.newInstance(order.EndDate, midnight) : null;
            Integer userCount = 100;

            Contact shipToContact = [SELECT Email 
                                       FROM Contact 
                                       WHERE Id IN (SELECT ShipToContactId FROM Order WHERE Id = :order.Id)
                                       LIMIT 1];

            List<OrderItem> userPacks = [SELECT Quantity
                                         FROM OrderItem 
                                         WHERE OrderId = :order.Id 
                                           AND Product2Id IN (SELECT Id FROM Product2 WHERE ProductCode IN ('slackernews-users'))];
            for (OrderItem item : userPacks) {
                userCount += item.Quantity.IntValue();
            }

            List<Entitlement> entitlements = new List<Entitlement>();
            entitlements.add(new Entitlement('member_count_max', String.ValueOf(userCount)));

            this.name = account.Name;
            this.custom_id = account.Id;
            this.app_id = app.id;
            this.channel_id = app.channel;
            this.email = shipToContact.Email;
            this.entitlementValues = entitlements; // Initialize as an empty list
            this.expires_at = (expirationDate != null) ? expirationDate.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
            this.is_geoaxis_supported = false;
            this.is_gitops_supported = false;
            this.is_identity_service_supported = false;
            this.is_support_bundle_upload_enabled = true;
            this.type = 'prod';

            if (app.productCode == 'slackernews-admin-console' || app.productCode == 'slackernews-admin-console-lts') {
                this.is_kots_install_enabled = true;
                this.is_helmvm_download_enabled = false;
                this.is_airgap_enabled = false;
                this.is_snapshot_supported = true ;
            } else if (app.productCode == 'slackernes-embedded-cluster' || app.productCode == 'slackernes-embedded-cluster-lts') {
                this.is_kots_install_enabled = true;
                this.is_helmvm_download_enabled = true;
                this.is_airgap_enabled = false;
                this.is_snapshot_supported = true ;
            } else if (app.productCode == 'slackernews-airgap' || app.productCode == 'slackernews-airgap-lts') {
                this.is_airgap_enabled = true;
                this.is_kots_install_enabled = true;
                this.is_helmvm_download_enabled = true;
                this.is_snapshot_supported = true ;
            } else {
                this.is_kots_install_enabled = false;
                this.is_helmvm_download_enabled = false;
                this.is_airgap_enabled = false;
                this.is_snapshot_supported = false ;
            }
        }
    }

}
