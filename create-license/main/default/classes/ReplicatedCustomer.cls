public class ReplicatedCustomer {
    public String id { get; set; }
    public String name { get; set; }
    public String customId { get; set; }
    public String appId { get; set; }
    public String channelId { get; set; }
    public String email { get; set; }
    public List<ReplicatedLicenseEntitlement> entitlementValues { get; set; } 
    public String expiresAt { get; set; }
    public Boolean isAirgapEnabled { get; set; }
    public Boolean isGeoaxisSupported { get; set; }
    public Boolean isGitopsSupported { get; set; }
    public Boolean isEmbeddedClusterDownloadEnabled { get; set; }
    public Boolean isIdentityServiceSupported { get; set; }
    public Boolean isKotsInstallEnabled { get; set; }
    public Boolean isSupportBundleUploadEnabled { get; set; }
    public Boolean isSnapshotSupported { get; set; }
    public Boolean isDisasterRecoverySupported { get; set; }
    public String type { get; set; }

    public String licenseId { get; set; }

    public String createRequest() {
        // the create request expects snake case for most attributes
        Map<String, Object> snakeCaseMap = new Map<String, Object>();

        snakeCaseMap.put('name', this.name);
        snakeCaseMap.put('custom_id', this.customId);
        snakeCaseMap.put('app_id', this.appId);
        snakeCaseMap.put('channel_id', this.channelId);
        snakeCaseMap.put('email', this.email);
        snakeCaseMap.put('expires_at', this.expiresAt);
        snakeCaseMap.put('is_airgap_enabled', this.isAirgapEnabled);
        snakeCaseMap.put('is_geoaxis_supported', this.isGeoaxisSupported);
        snakeCaseMap.put('is_gitops_supported', this.isGitopsSupported);
        snakeCaseMap.put('is_embedded_cluster_download_enabled', this.isEmbeddedClusterDownloadEnabled);
        snakeCaseMap.put('is_identity_service_supported', this.isIdentityServiceSupported);
        snakeCaseMap.put('is_kots_install_enabled', this.isKotsInstallEnabled);
        snakeCaseMap.put('is_support_bundle_upload_enabled', this.isSupportBundleUploadEnabled);
        snakeCaseMap.put('is_snapshot_supported', this.isSnapshotSupported);
        snakeCaseMap.put('is_disaster_recovery_supported', this.isDisasterRecoverySupported);
        snakeCaseMap.put('type', this.type);


        List<Object> entitlements = new List<Object>();
        for (ReplicatedLicenseEntitlement entitlement : this.entitlementValues) {
            Map<String, Object> entitlementMap = new Map<String, Object>();
            entitlementMap.put('name', entitlement.name);
            entitlementMap.put('value', entitlement.value);
            entitlementMap.put('is_default', entitlement.isDefault);
            entitlements.add(entitlementMap);
        }

        // the request expects snake case for everything but entitlementValues
        snakeCaseMap.put('entitlementValues', entitlements);

        // Convert the map to JSON string
        return JSON.serialize(snakeCaseMap);
    }

    // Constructor
    public ReplicatedCustomer(OrderTerms terms) {
        Time midnight = Time.newInstance(0,0,0,0);
        DateTime expirationDate = Datetime.newInstance(terms.endDate(), midnight) ;

        List<ReplicatedLicenseEntitlement> entitlements = terms.entitlements() ;

        this.name = terms.customerName();
        this.customId = terms.accountId();
        this.appId = terms.applicationId();
        this.channelId = terms.channelId();
        this.email = terms.customerEmail();
        this.entitlementValues = entitlements; // Initialize as an empty list
        this.expiresAt = (expirationDate != null) ? expirationDate.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
        this.isGeoaxisSupported = false;
        this.isGitopsSupported = false;
        this.isIdentityServiceSupported = false;
        this.type = 'prod';

        this.isKotsInstallEnabled = terms.isAdminConsoleEnabled();
        this.isEmbeddedClusterDownloadEnabled = terms.isEmbeddedClusterEnabled();
        this.isAirgapEnabled = terms.isAirgapEnabled();
        this.isSupportBundleUploadEnabled = terms.isSupportBundleUploadEnabled() ;
        this.isSnapshotSupported = terms.isSnapshotSupported() ;
        this.isDisasterRecoverySupported = terms.isDisasterRecoverySupported() ;
    }
  
    // Factory method that initializes the object from the provided JSON
    public static ReplicatedCustomer create (String jsonString) {
        ReplicatedCustomer customer = (ReplicatedCustomer) JSON.deserialize(jsonString, ReplicatedCustomer.class);

        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
        customer.licenseId = (String) jsonMap.get('installationId');

        return customer;
    }  
}


