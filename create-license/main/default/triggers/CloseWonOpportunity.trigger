trigger CloseWonOpportunity on Contract (after update) {
    List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

    for (Contract contract : Trigger.new) {
        if (contract.Status == 'Activated' && Trigger.oldMap.get(contract.Id).Status != 'Activated') {
            Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Id IN ( SELECT OpportunityId FROM Order WHERE ContractId = :contract.Id )];
            opp.StageName = 'Closed Won';
            opportunitiesToUpdate.add(opp);
        }
    }

    if (!opportunitiesToUpdate.isEmpty()) {
        update opportunitiesToUpdate;
    }
}