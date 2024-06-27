trigger CreateLicense on Contract (after update) {
    for (Contract contract : Trigger.new) {
        if (contract.Status == 'Executed' && Trigger.oldMap.get(contract.Id).Status != 'Executed') {
            System.enqueueJob(new ReplicatedLicense(contract));
        }
    }
}
