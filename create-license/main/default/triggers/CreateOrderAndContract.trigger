trigger CreateOrderAndContract on Opportunity (after update) {
    List<Opportunity> negotiating = new List<Opportunity>();

    for (Opportunity opp : Trigger.new) {
        if (opp.StageName == 'Negotiation/Review'
                && Trigger.oldMap.get(opp.Id).StageName != 'Negotiation/Review') {
            negotiating.add(opp);
        }
    }

    if (negotiating.isEmpty()) {
        return;
    }

    // Collect Opportunity IDs for bulk queries.
    Set<Id> oppIds = new Set<Id>();
    for (Opportunity opp : negotiating) {
        oppIds.add(opp.Id);
    }

    // Bulk query Technical Buyer contacts for ShipToContactId.
    Map<Id, Id> contactByOppId = new Map<Id, Id>();
    for (OpportunityContactRole ocr : [
        SELECT OpportunityId, ContactId
        FROM OpportunityContactRole
        WHERE OpportunityId IN :oppIds AND Role = 'Technical Buyer'
    ]) {
        if (!contactByOppId.containsKey(ocr.OpportunityId)) {
            contactByOppId.put(ocr.OpportunityId, ocr.ContactId);
        }
    }

    // Fallback: for Opportunities without a Technical Buyer, use any Contact on the Account.
    Set<Id> accountIdsNeedingContact = new Set<Id>();
    for (Opportunity opp : negotiating) {
        if (!contactByOppId.containsKey(opp.Id)) {
            accountIdsNeedingContact.add(opp.AccountId);
        }
    }
    if (!accountIdsNeedingContact.isEmpty()) {
        Map<Id, Id> contactByAccountId = new Map<Id, Id>();
        for (Contact c : [
            SELECT Id, AccountId FROM Contact
            WHERE AccountId IN :accountIdsNeedingContact
            ORDER BY CreatedDate ASC LIMIT 1
        ]) {
            if (!contactByAccountId.containsKey(c.AccountId)) {
                contactByAccountId.put(c.AccountId, c.Id);
            }
        }
        for (Opportunity opp : negotiating) {
            if (!contactByOppId.containsKey(opp.Id) && contactByAccountId.containsKey(opp.AccountId)) {
                contactByOppId.put(opp.Id, contactByAccountId.get(opp.AccountId));
            }
        }
    }

    // Create Contracts first.
    List<Contract> contracts = new List<Contract>();
    List<Opportunity> contractOpps = new List<Opportunity>();
    for (Opportunity opp : negotiating) {
        OrderTerms terms = new OrderTerms(opp);
        contracts.add(new Contract(
            AccountId = opp.AccountId,
            Status = 'Draft',
            ContractTerm = terms.months(),
            StartDate = terms.effectiveDate()
        ));
        contractOpps.add(opp);
    }
    insert contracts;

    // Create Orders linked to Contracts.
    List<Order> orders = new List<Order>();
    for (Integer i = 0; i < contractOpps.size(); i++) {
        Opportunity opp = contractOpps[i];
        OrderTerms terms = new OrderTerms(opp);
        orders.add(new Order(
            AccountId = opp.AccountId,
            OpportunityId = opp.Id,
            ContractId = contracts[i].Id,
            Pricebook2Id = opp.Pricebook2Id,
            Status = 'Draft',
            EffectiveDate = terms.effectiveDate(),
            EndDate = terms.endDate(),
            ShipToContactId = contactByOppId.get(opp.Id)
        ));
    }
    insert orders;

    // Map Opportunity ID to Order ID for line item copy.
    Map<Id, Id> orderByOppId = new Map<Id, Id>();
    for (Order o : orders) {
        orderByOppId.put(o.OpportunityId, o.Id);
    }

    // Copy OpportunityLineItems to OrderItems.
    List<OrderItem> orderItems = new List<OrderItem>();
    for (OpportunityLineItem oli : [
        SELECT OpportunityId, PricebookEntryId, Quantity, UnitPrice
        FROM OpportunityLineItem
        WHERE OpportunityId IN :oppIds
    ]) {
        orderItems.add(new OrderItem(
            OrderId = orderByOppId.get(oli.OpportunityId),
            PricebookEntryId = oli.PricebookEntryId,
            Quantity = oli.Quantity,
            UnitPrice = oli.UnitPrice
        ));
    }
    if (!orderItems.isEmpty()) {
        insert orderItems;
    }
}
