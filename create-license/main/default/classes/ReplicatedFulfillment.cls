public class ReplicatedFulfillment implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;

    private ReplicatedPlatform platform;
    private ReplicatedCustomer customer;
    private ReplicatedApplication app;
    private ReplicatedChannel channel;

    // store install instructions to work around transaction boundaries
    private String helmInstallInstructions;
    private String airgapInstallInstructions;
    private String embeddedClusterInstallInstructions;
    private String kotsInstallInstructions;

    public ReplicatedFulfillment(OrderTerms terms) {
        this.terms = terms;
        this.customer = new ReplicatedCustomer(terms);
        ReplicatedVendorPortalCredential__mdt defaultCredential = [
            SELECT ApiToken__c 
            FROM ReplicatedVendorPortalCredential__mdt 
            WHERE DeveloperName = 'Default' 
            LIMIT 1
        ];

        this.platform = new ReplicatedPlatform(defaultCredential);
    }

    private void setLicenseId(String licenseId) {
        Id orderId = this.terms.orderId();
        Order order = [SELECT Id, LicenseId__c FROM Order WHERE Id = :orderId LIMIT 1];
        order.LicenseId__c = licenseId;
        update order ;
    }

    private void attachLicense(String license) {
        this.attachFile('Software License', 'license.yaml', license);
    }

        
    private void attachFile(String title, String fileName, String content) {
        Id orderId = this.terms.orderId();
        Blob contentBlob = Blob.valueOf(content);
        
        // Create ContentVersion
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.VersionData = contentBlob;
        contentVersion.Title = title; 
        contentVersion.PathOnClient = fileName;
        
        insert contentVersion;
        
        // Get ContentDocumentId
        Id licenseDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id =:contentVersion.Id].ContentDocumentId;
        
        // Create ContentDocumentLink
        ContentDocumentLink docLink = new ContentDocumentLink();
        docLink.ContentDocumentId = licenseDocId;
        docLink.LinkedEntityId = orderId;
        docLink.ShareType = 'V'; 
        docLink.Visibility = 'AllUsers'; 
        
        insert docLink;
    }

    private void prepareInstallInstructions() {
        ReplicatedInstallInstructions instructions = new ReplicatedInstallInstructions(this.platform, this.app, this.customer, this.channel);
        this.helmInstallInstructions = instructions.helmInstall();
        this.airgapInstallInstructions = instructions.airgapInstall();
        this.embeddedClusterInstallInstructions = instructions.embeddedClusterInstall();
        this.kotsInstallInstructions = instructions.kotsInstall();
    }
        
    private void attachInstallInstructions() {
        attachFile(this.app.name + ' Helm Install Instructions', 'helm-install-instructions.txt', this.helmInstallInstructions);

        if ( this.terms.isAirgapEnabled() ) {
            attachFile(this.app.name + ' Airgap Install Instructions', 'airgap-install-instructions.txt', this.airgapInstallInstructions);
        }

        if ( this.terms.isEmbeddedClusterEnabled() ) {
            attachFile(this.app.name + ' Embedded Cluster Install Instructions', 'embedded-cluster-install-instructions.txt', this.embeddedClusterInstallInstructions);
        }

        if ( this.terms.isAdminConsoleEnabled() ) {
            attachFile(this.app.name + ' Admin Console Install Instructions', 'kots-install-instructions.txt', this.kotsInstallInstructions);
        }
    }

    public void sendInstallInstructions() {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        OrgWideEmailAddress address = [SELECT Id FROM OrgWideEmailAddress 
                                   WHERE DisplayName = 'Fulfillment' LIMIT 1]; 
        email.setOrgWideEmailAddressId(address.Id); 
        
        Id orderId = this.terms.orderId();
        List<ContentDocumentLink> orderAttachments = [SELECT ContentDocumentId 
                                          FROM ContentDocumentLink 
                                          WHERE LinkedEntityId = :orderId];
        
        Set<Id> orderAttachmentIds = new Set<Id>();
        for (ContentDocumentLink attachment : orderAttachments) {
            orderAttachmentIds.add(attachment.ContentDocumentId);
        }

        String instructions = 'helm-install-instructions.txt';
        if ( this.terms.isAirgapEnabled() ) {
            instructions = 'airgap-install-instructions.txt';
        } else if ( this.terms.isEmbeddedClusterEnabled() ) {
            instructions = 'embedded-cluster-install-instructions.txt';
        } else if ( this.terms.isAdminConsoleEnabled() ) {
            instructions = 'kots-install-instructions.txt';

            // attach the license file needed to install
            ContentVersion license = [SELECT VersionData, Title 
                                      FROM ContentVersion 
                                      WHERE ContentDocumentId IN :orderAttachmentIds
                                        AND PathOnClient = 'license.yaml'
                                        AND IsLatest = true 
                                      LIMIT 1];

             Messaging.EmailFileAttachment licenseAttachment = new Messaging.EmailFileAttachment();
             licenseAttachment.setFileName('license.yaml');
             licenseAttachment.setBody(license.VersionData);
        
             email.setFileAttachments(new Messaging.EmailFileAttachment[] { licenseAttachment });
        }

        ContentVersion content = [SELECT VersionData, Title 
                                  FROM ContentVersion 
                                  WHERE ContentDocumentId IN :orderAttachmentIds
                                    AND PathOnClient = :instructions
                                    AND IsLatest = true 
                                  LIMIT 1];

        email.setToAddresses(new String[] { this.terms.customerEmail() });
        email.setSubject(content.Title);
        email.setPlainTextBody(content.VersionData.toString());
        
        // Send the email
        try {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
        } catch (Exception e) {
            System.debug('Error sending email: ' + e.getMessage());
        }
    }

    public void execute(QueueableContext context) {
        String licenseId = null ; 
        if ( !this.platform.customerExists(this.terms) ) {
            licenseId = this.platform.createLicense(this.terms);
            this.customer.licenseId = licenseId;
        } else {
            ReplicatedCustomer customer = this.platform.loadCustomer(this.terms);
            licenseId = customer.licenseId;
            customer.updateTerms(this.terms);
            this.platform.updateCustomer(customer); 
        }

        String license = this.platform.getLicenseFile(this.terms);
        
        this.app = this.platform.loadApplication(this.terms.applicationId());
        this.channel = this.platform.loadChannel(this.terms.applicationId(), this.terms.channelId());
        this.prepareInstallInstructions();

        this.setLicenseId(licenseId);
        this.attachLicense(license);
        this.attachInstallInstructions();
        this.sendInstallInstructions();
    }
}
