trigger CreateLicense on Contract (after update) {
    for (Contract contract : Trigger.new) {
        if (contract.Status == 'Activated' && Trigger.oldMap.get(contract.Id).Status != 'Activated') {
            System.enqueueJob(new ReplicatedLicense(contract));
        }
    }
}