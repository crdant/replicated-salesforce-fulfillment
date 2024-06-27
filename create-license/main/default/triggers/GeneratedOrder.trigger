trigger GenerateOrder on Opportunity (after update) {
    List<Order> ordersToInsert = new List<Order>();
    List<OrderItem> orderItemsToInsert = new List<OrderItem>();

    for (Opportunity opp : Trigger.new) {
        if (opp.StageName == 'Closed Won' && Trigger.oldMap.get(opp.Id).StageName != 'Closed Won') {
            // Create an order
            Order newOrder = new Order(
                AccountId = opp.AccountId,
                OpportunityId = opp.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft'
            );
            ordersToInsert.add(newOrder);
        }
    }
    
    if (!ordersToInsert.isEmpty()) {
        insert ordersToInsert;
        
        // Query for the inserted orders to get their IDs
        List<Order> insertedOrders = [SELECT Id, OpportunityId FROM Order WHERE OpportunityId IN :Trigger.newMap.keySet()];
        
        // Create order items for each order
        for (Order ord : insertedOrders) {
            List<OpportunityLineItem> oppLineItems = [
                SELECT Id, PricebookEntryId, Quantity, UnitPrice
                FROM OpportunityLineItem
                WHERE OpportunityId = :ord.OpportunityId
            ];
            for (OpportunityLineItem oli : oppLineItems) {
                OrderItem newOrderItem = new OrderItem(
                    OrderId = ord.Id,
                    PricebookEntryId = oli.PricebookEntryId,
                    Quantity = oli.Quantity,
                    UnitPrice = oli.UnitPrice
                );
                orderItemsToInsert.add(newOrderItem);
            }
        }

        if (!orderItemsToInsert.isEmpty()) {
            insert orderItemsToInsert;
        }
    }
}

