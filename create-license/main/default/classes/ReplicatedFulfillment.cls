public class ReplicatedLicense implements Queueable, Database.AllowsCallouts {
    private OrderTerms terms;
    private ReplicatedCustomer customer;

    public ReplicatedLicense(OrderTerms terms) {
        this.terms = terms;
        this.customer = new ReplicatedCustomer(terms);
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

    private void attachInstallInstructions() {
        ReplicatedInstallInstructions instructions = new ReplicatedInstallInstructions(this.customer);
        
        attachFile('Helm Install Instructions', 'helm-install-instructions.txt', instructions.helmInstall());

        if ( this.terms.isEmbeddedClusterEnabled() ) {
            attachFile('Embedded Cluster Install Instructions', 'embedded-cluster-install-instructions.txt', instructions.embeddedClusterInstall());
        }

        if ( this.terms.isAdminConsoleEnabled() ) {
            attachFile('KOTS Install Instructions', 'kots-install-instructions.txt', instructions.kotsInstall());
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
        if ( this.terms.isEmbeddedClusterEnabled() ) {
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
            System.debug('Email sent successfully with attachment');
        } catch (Exception e) {
            System.debug('Error sending email: ' + e.getMessage());
        }
    }

    public void execute(QueueableContext context) {
        ReplicatedVendorPortalCredential__mdt defaultCredential = [
            SELECT ApiToken__c 
            FROM ReplicatedVendorPortalCredential__mdt 
            WHERE DeveloperName = 'Default' 
            LIMIT 1
        ];

        ReplicatedPlatform platform = new ReplicatedPlatform(defaultCredential);
        if ( !platform.customerExists(this.terms) ) {
            String licenseId = platform.createLicense(this.terms);
            String license = platform.getLicenseFile(this.terms);

            // it may be tempting to pair this with the createLicense call above, but 
            // it will create transaction issues since the call to get the license file
            // invokes an HTTP callout which will fail due to an uncommitted transaction
            this.setLicenseId(licenseId);
            this.attachLicense(license);
            this.attachInstallInstructions();
            this.sendInstallInstructions();

            return;
        } else {
          System.debug('TO DO: Handle existing customer');
        }
        
    }
}
