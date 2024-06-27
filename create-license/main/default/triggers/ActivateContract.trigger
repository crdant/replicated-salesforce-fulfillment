trigger ActivateContract on Order (after update) {
    List<Contract> contractsToUpdate = new List<Contract>();

    for (Order order : Trigger.new) {
        if (order.Status == 'Activated' && Trigger.oldMap.get(order.Id).Status != 'Activated') {
            Contract contract = [SELECT Id, Status FROM Contract WHERE Id = :order.ContractId] ;
            contract.Status = 'Activated';
            contractsToUpdate.add(contract);
        }
    }

    if (!contractsToUpdate.isEmpty()) {
        update contractsToUpdate;
    }
}
