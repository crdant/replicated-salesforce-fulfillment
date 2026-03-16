trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    for (Replicated_Webhook__e event : Trigger.New) {
        String eventType = event.Event_Type__c;
        System.debug('Received Replicated webhook: ' + eventType +
            ' for customer: ' + event.Customer_Id__c);

        // Route to appropriate handler based on event type.
        // Handler implementations are in separate issues (#11, #12).
        switch on eventType {
            when else {
                System.debug('Unhandled Replicated webhook event type: ' + eventType);
            }
        }
    }

    EventBus.TriggerContext.currentContext().setResumeCheckpoint(
        Trigger.New[Trigger.New.size() - 1].ReplayId
    );
}
