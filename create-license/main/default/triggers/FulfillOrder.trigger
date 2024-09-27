trigger FulfillOrder on Order (after update) {
    for (Order order : Trigger.new) {
        System.debug('Fulfilling order for ' + order.Id + ', status ' + order.Status);
        if (order.Status == 'Activated' && Trigger.oldMap.get(order.Id).Status != 'Activated') {
            LicenseTerms terms = new LicenseTerms(order);
            System.enqueueJob(new ReplicatedFulfillment(terms));
        }
    }
}
