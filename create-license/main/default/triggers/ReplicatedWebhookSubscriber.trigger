trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    // Collect events by handler type to avoid hitting the 50 Queueable job governor limit.
    // Platform Event triggers can receive up to 2,000 events per batch.
    List<Replicated_Webhook__e> instanceEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> licenseExpiringEvents = new List<Replicated_Webhook__e>();

    for (Replicated_Webhook__e event : Trigger.New) {
        // Avoid logging payload or customer data -- debug logs are visible to admins.
        if (String.isBlank(event.Payload__c)) {
            continue;
        }

        switch on event.Event_Type__c {
            when 'instance.created', 'instance.upgraded', 'instance.inactive' {
                instanceEvents.add(event);
            }
            when 'customer.license.expiring' {
                licenseExpiringEvents.add(event);
            }
            when 'Pending Self-Service Signup' {
                System.enqueueJob(new TrialSignupHandler(event.Payload__c));
            }
            when 'customer.created' {
                System.enqueueJob(new CustomerCreatedHandler(event.Payload__c));
            }
            when 'Release Assets Downloaded' {
                System.enqueueJob(new AssetDownloadedHandler(event.Payload__c));
            }
            when else {
                System.debug('Unhandled Replicated webhook event type: ' + event.Event_Type__c);
            }
        }
    }

    if (!instanceEvents.isEmpty()) {
        System.enqueueJob(new InstanceEventHandler(instanceEvents));
    }
    if (!licenseExpiringEvents.isEmpty()) {
        System.enqueueJob(new LicenseExpiringHandler(licenseExpiringEvents));
    }

    EventBus.TriggerContext.currentContext().setResumeCheckpoint(
        Trigger.New[Trigger.New.size() - 1].ReplayId
    );
}
