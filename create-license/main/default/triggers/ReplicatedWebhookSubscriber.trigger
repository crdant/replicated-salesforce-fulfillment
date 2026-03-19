trigger ReplicatedWebhookSubscriber on Replicated_Webhook__e (after insert) {
    // Collect events by handler type to avoid hitting the 50 Queueable job governor limit.
    // Platform Event triggers can receive up to 2,000 events per batch.
    List<Replicated_Webhook__e> instanceEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> licenseExpiringEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> signupEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> customerCreatedEvents = new List<Replicated_Webhook__e>();
    List<Replicated_Webhook__e> assetDownloadedEvents = new List<Replicated_Webhook__e>();

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
                signupEvents.add(event);
            }
            when 'customer.created' {
                customerCreatedEvents.add(event);
            }
            when 'Release Assets Downloaded' {
                assetDownloadedEvents.add(event);
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
    if (!signupEvents.isEmpty()) {
        System.enqueueJob(new TrialSignupHandler(signupEvents));
    }
    if (!customerCreatedEvents.isEmpty()) {
        System.enqueueJob(new CustomerCreatedHandler(customerCreatedEvents));
    }
    if (!assetDownloadedEvents.isEmpty()) {
        System.enqueueJob(new AssetDownloadedHandler(assetDownloadedEvents));
    }

    EventBus.TriggerContext.currentContext().setResumeCheckpoint(
        Trigger.New[Trigger.New.size() - 1].ReplayId
    );
}
