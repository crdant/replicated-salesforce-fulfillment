trigger ExecuteOrder on Order (after update) {
    List<Contract> contractsToInsert = new List<Contract>();

    for (Order order : Trigger.new) {
        if (order.Status == 'Activated' && Trigger.oldMap.get(order.Id).Status != 'Activated') {
            Contract newContract = new Contract(
                AccountId = order.AccountId,
                StartDate = order.EffectiveDate,
                ContractTerm = 12, // Example term, adjust as needed
                OwnerId = order.OwnerId,
                Status = 'Draft', // Initial status of the contract
                OrderId__c = order.Id // Assuming you have a custom field to link to the order
            );
            
            
            contractsToInsert.add(newContract);
        }
    }

    if (!contractsToInsert.isEmpty()) {
      insert contractsToInsert;

      List<Contract> contractsToUpdate = new List<Contract>();
      for (Contract contract : contractsToInsert) {
          contract.Status = 'Executed'; 
          contractsToUpdate.add(contract);

          List<OrderItem> orderItems = [SELECT Quantity, UnitPrice, PricebookEntryId FROM OrderItem WHERE OrderId = :contract.OrderId__c];
          for (OrderItem item : orderItems) {
              ContractLineItem newContractLineItem = new ContractLineItem(
                  ContractId = contract.Id,
                  Quantity = item.Quantity,
                  UnitPrice = item.UnitPrice,
                  PricebookEntryId = item.PricebookEntryId
              );
              contractLineItemsToInsert.add(newContractLineItem);
          }
      }

      if (!contractLineItemsToInsert.isEmpty()) {
          insert contractLineItemsToInsert;
      }
      
      update contractsToUpdate;
  }

}
