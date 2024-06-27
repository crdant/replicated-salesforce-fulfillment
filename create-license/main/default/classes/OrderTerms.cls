public class OrderTerms {
    private Date closeDate;
    private Integer years;

    public OrderTerms(Opportunity opp) {
        OpportunityLineItem coreProduct = [ SELECT Quantity
                                            FROM OpportunityLineItem
                                            WHERE OpportunityId = :opp.Id
                                              AND Product2Id IN (SELECT Id FROM Product2 WHERE ProductCode <> 'slackernews-users')];
        
        this.closeDate = opp.CloseDate;
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
}
