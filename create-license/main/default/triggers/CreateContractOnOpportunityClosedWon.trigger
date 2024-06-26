trigger CreateContractOnOpportunityClosedWon on Opportunity (after update) {
    List<Contract> contractsToInsert = new List<Contract>();
    
    for (Opportunity opp : Trigger.new) {
        if (opp.StageName == 'Closed Won' && Trigger.oldMap.get(opp.Id).StageName != 'Closed Won') {
            Contract newContract = new Contract(
                AccountId = opp.AccountId,
                StartDate = Date.today(),
                ContractTerm = 12, // Example term, adjust as needed
                OwnerId = opp.OwnerId,
                Status = 'Draft', // Initial status of the contract
                
                isAdminConsoleEnabled__c = opp.isAdminConsoleEnabled__c,
                isEmbeddedClusterEnabled__c = opp.isEmbeddedClusterEnabled__c,
                isAirgapEnabled__c = opp.isAirgapEnabled__c,
                isSupportBundleUploadEnabled__c = opp.isSupportBundleUploadEnabled__c,
                isSnapshotSupported__c = opp.isSnapshotSupported__c
            );
            contractsToInsert.add(newContract);
        }
    }
    
    if (!contractsToInsert.isEmpty()) {
        insert contractsToInsert;

        List<Contract> contractsToUpdate = new List<Contract>();
        for (Contract c : contractsToInsert) {
            c.Status = 'Activated'; 
            contractsToUpdate.add(c);
        }

        update contractsToUpdate;
    }
}