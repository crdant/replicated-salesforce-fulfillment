trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    for (Replicated_Webhook__e event : Trigger.New) {
        // Route to appropriate handler based on event type.
        // Avoid logging payload or customer data -- debug logs are visible to admins.
        switch on event.Event_Type__c {
            when 'instance.created', 'instance.upgraded', 'instance.inactive' {
                System.enqueueJob(new InstanceEventHandler(
                    event.Event_Type__c, event.Customer_Id__c, event.Payload__c
                ));
            }
            when 'customer.license.expiring' {
                System.enqueueJob(new LicenseExpiringHandler(
                    event.Customer_Id__c, event.Payload__c
                ));
            }
            when else {
                System.debug('Unhandled Replicated webhook event type: ' + event.Event_Type__c);
            }
        }
    }

    EventBus.TriggerContext.currentContext().setResumeCheckpoint(
        Trigger.New[Trigger.New.size() - 1].ReplayId
    );
}
