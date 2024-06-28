trigger ActivateOrder on Contract (after update) {
    List<Order> ordersToUpdate = new List<Order>();

    for (Contract contract : Trigger.new) {
        if (contract.Status == 'Activated' && Trigger.oldMap.get(contract.Id).Status != 'Activated') {
            Order order = [SELECT Id, Status FROM Order WHERE ContractId = :contract.Id] ;
            order.Status = 'Activated';
            ordersToUpdate.add(order);
        }
    }

    if (!ordersToUpdate.isEmpty()) {
        update ordersToUpdate;
    }
}