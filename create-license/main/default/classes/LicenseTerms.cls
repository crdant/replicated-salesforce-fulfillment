public class LicenseTerms {
    private Id opportunityId ;

    private Date closeDate;
    private Integer years;

    public LicenseTerms(Id opportunityId) {
        Opportunity opp = [SELECT Id, CloseDate
                           FROM Opportunity 
                           WHERE Id = :opportunityId
                           LIMIT 1];
        this.initialize(opp);
    }

    public LicenseTerms(Order order) {
        Opportunity opp = [SELECT Id, CloseDate
                           FROM Opportunity 
                           WHERE Id = :order.OpportunityId
                           LIMIT 1];
        this.initialize(opp);
    }

    public LicenseTerms(Opportunity opp) {
        this.initialize(opp);
    }

    private void initialize(Opportunity opp) {
        this.opportunityId = opp.Id;
        this.closeDate = opp.CloseDate;

        OpportunityLineItem coreProduct = [ SELECT Quantity
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opportunityId
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE Product2.IsAddOn__c = false )];
        
        this.years = coreProduct.Quantity.intValue();
    }

    public Date effectiveDate() {
        // Add the years (in years) to the close date
        Integer year = closeDate.year();
        Integer month = closeDate.month();

        return Date.newInstance(year, month + 1, 1);
    }

    public Date endDate() {
        // Add the years (in years) to the close date
        Date fromNow = closeDate.addYears(years);

        // Find the last day of the month for the new date
        Integer year = fromNow.year();
        Integer month = fromNow.month();
        Integer lastDayOfMonth = Date.daysInMonth(year, month);

        return Date.newInstance(year, month, lastDayOfMonth);
    }

    public Integer months() {
        return years * 12 ; 
    }

    public String customerName() {
        Opportunity opp = [SELECT Id, Account.Name 
                           FROM Opportunity 
                           WHERE Id = :opportunityId
                           LIMIT 1];
        return opp.Account.Name; 
    }

    public String applicationId() {
        OpportunityLineItem app = [ SELECT Product2.Application__c
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opportunityId
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE Product2.IsAddOn__c = false )];
        
        return app.Product2.Application__c; 
    }

    public String channelId() {
        OpportunityLineItem app = [ SELECT Product2.ReleaseChannel__c
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opportunityId
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE Product2.IsAddOn__c = false )];
        
        return app.Product2.ReleaseChannel__c; 
    }

    public Id orderId() {
        Order order = [SELECT Id 
                       FROM Order 
                       WHERE opportunityId = :opportunityId
                       LIMIT 1];
        return order.Id; 
    }

    public Id accountId() {
        Opportunity opp = [SELECT AccountId
                           FROM Opportunity 
                           WHERE Id = :opportunityId
                           LIMIT 1];
        return opp.accountId; 
    }

    public String customerEmail() {
        Contact shipToContact = [SELECT Email 
                                 FROM Contact 
                                 WHERE Id IN ( select ShipToContactId FROM Order WHERE OpportunityId = :opportunityId)
                                 LIMIT 1];
        return shipToContact.Email; 
    }

    private Integer userCount() {
        List<OpportunityLineItem> userPacks = [SELECT Id, Quantity
                                               FROM OpportunityLineItem
                                               WHERE OpportunityId = :opportunityId
                                                 AND Product2Id IN (SELECT Id FROM Product2 WHERE ProductCode IN ('slackernews-users'))];
        Integer userCount = 100;
        for (OpportunityLineItem userPack : userPacks) {
            userCount += userPack.Quantity.intValue();
        }
        return userCount;
    }

    public List<ReplicatedLicenseEntitlement> entitlements() {
        List<ReplicatedLicenseEntitlement> entitlements = new List<ReplicatedLicenseEntitlement>();
        entitlements.add(new ReplicatedLicenseEntitlement('member_count_max', String.ValueOf(userCount())));
        return entitlements;
    }

    public Boolean isAdminConsoleEnabled() {
        OpportunityLineItem coreProduct = [ SELECT Id, Product2.IsAdminConsoleEnabled__c
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opportunityId
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE IsAddOn__c = false )];
        System.debug('isAdminConsoleEnabled: ' + coreProduct.Product2.IsAdminConsoleEnabled__c);
        return coreProduct.Product2.IsAdminConsoleEnabled__c;
    }

    public Boolean isEmbeddedClusterEnabled() {
        OpportunityLineItem coreProduct = [ SELECT Id, Product2.IsEmbeddedClusterEnabled__c
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opportunityId
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE IsAddOn__c = false )];
        System.debug('isEmbeddedClusterEnabled: ' + coreProduct.Product2.IsEmbeddedClusterEnabled__c);
        return coreProduct.Product2.IsEmbeddedClusterEnabled__c;
    }

    public Boolean isAirgapEnabled() {
        OpportunityLineItem coreProduct = [ SELECT Id, Product2.IsAirgapEnabled__c
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opportunityId
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE IsAddOn__c = false )];
        System.debug('isAirgapEnabled: ' + coreProduct.Product2.IsAirgapEnabled__c);
        return coreProduct.Product2.IsAirgapEnabled__c;
    }

    public Boolean isSupportBundleUploadEnabled() {
        return isAdminConsoleEnabled();
    }

    public Boolean isSnapshotSupported() {
        return isAdminConsoleEnabled();
    }

    public Boolean isDisasterRecoverySupported() {
        return isEmbeddedClusterEnabled();
    }

}
