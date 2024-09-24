trigger FulfillOrder on Order (after update) {
    for (Order order : Trigger.new) {
        System.debug('Creating Licensse for ' + order.Id + ', status ' + order.Status);
        if (order.Status == 'Activated' && Trigger.oldMap.get(order.Id).Status != 'Activated') {
            OrderTerms terms = new OrderTerms(order);
            System.enqueueJob(new ReplicatedFulfillment(terms));
        }
    }
}
