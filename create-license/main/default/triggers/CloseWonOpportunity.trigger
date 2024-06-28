trigger CloseWonOpportunity on Opportunity (after update) {
    List<Order> ordersToInsert = new List<Order>();
    List<OrderItem> orderItemsToInsert = new List<OrderItem>();
    List<Contract> contractsToInsert = new List<Contract>();

    for (Opportunity opp : Trigger.new) {
        if (opp.StageName == 'Closed Won' && Trigger.oldMap.get(opp.Id).StageName != 'Closed Won') {
            OrderTerms orderTerms = new OrderTerms(opp);
            Date effectiveDate = orderTerms.effectiveDate();
            Date endDate = orderTerms.endDate();
            Integer term = orderTerms.months();

            Contract newContract = new Contract(
                AccountId = opp.AccountId,
                StartDate = effectiveDate,
                ContractTerm = term,
                OwnerId = opp.OwnerId,
                Status = 'Draft' // Initial status of the contract
            );
            contractsToInsert.add(newContract);

            if (!contractsToInsert.isEmpty()) {
                insert contractsToInsert;

                for ( Contract contract : contractsToInsert ) {
                    Order newOrder = new Order(
                        AccountId = opp.AccountId,
                        ContractId = contract.Id,
                        OpportunityId = opp.Id,
                        Pricebook2Id = opp.Pricebook2Id,
                        EffectiveDate = effectiveDate,
                        EndDate = endDate,
                        Status = 'Draft'
                    );
                    insert newOrder;
              
                    // Query for the inserted orders to get their IDs
                    List<Order> insertedOrders = [SELECT Id, OpportunityId FROM Order WHERE OpportunityId IN :Trigger.newMap.keySet()];
                    for (Order ord : insertedOrders) {
                        List<OpportunityLineItem> oppLineItems = [
                            SELECT Id, PricebookEntryId, Quantity, UnitPrice
                            FROM OpportunityLineItem
                            WHERE OpportunityId = :ord.OpportunityId
                        ];
                        for (OpportunityLineItem item : oppLineItems) {
                            OrderItem newOrderItem = new OrderItem(
                                OrderId = ord.Id,
                                PricebookEntryId = item.PricebookEntryId,
                                Quantity = item.Quantity,
                                UnitPrice = item.UnitPrice
                            );
                            orderItemsToInsert.add(newOrderItem);
                        }
                    }

                    if (!orderItemsToInsert.isEmpty()) {
                        insert orderItemsToInsert;
                    }
                }
            }
        }
    }
}