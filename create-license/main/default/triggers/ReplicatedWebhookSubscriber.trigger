trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    for (Replicated_Webhook__e event : Trigger.New) {
        // Route to appropriate handler based on event type.
        // Handler implementations are in separate issues (#11, #12).
        // Avoid logging payload or customer data -- debug logs are visible to admins.
        switch on event.Event_Type__c {
            when else {
                System.debug('Unhandled Replicated webhook event type: ' + event.Event_Type__c);
            }
        }
    }

    EventBus.TriggerContext.currentContext().setResumeCheckpoint(
        Trigger.New[Trigger.New.size() - 1].ReplayId
    );
}
