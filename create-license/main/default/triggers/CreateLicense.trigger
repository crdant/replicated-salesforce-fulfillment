trigger CreateLicense on Order (after update) {
    for (Order order : Trigger.new) {
        if (order.Status == 'Activated' && Trigger.oldMap.get(order.Id).Status != 'Activated') {
            System.enqueueJob(new ReplicatedLicense(order));
        }
    }
}
