public class TrialSignupHandler implements Queueable {
    private String payload;

    public TrialSignupHandler(String payload) {
        this.payload = payload;
    }

    public void execute(QueueableContext context) {
        Map<String, Object> webhookPayload = (Map<String, Object>) JSON.deserializeUntyped(this.payload);
        Map<String, Object> data = (Map<String, Object>) webhookPayload.get('data');

        String customerName = (String) data.get('customer_name');
        String email = (String) data.get('email');

        // Idempotent: skip if a Lead with this email already exists
        if (String.isNotBlank(email)) {
            List<Lead> existing = [
                SELECT Id FROM Lead
                WHERE Email = :email AND IsConverted = false
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                System.debug('TrialSignupHandler: Lead already exists for email ' + email + ', skipping');
                return;
            }
        }

        Lead lead = new Lead(
            FirstName = '',
            LastName = String.isNotBlank(customerName) ? customerName : 'Unknown',
            Company = String.isNotBlank(customerName) ? customerName : 'Unknown',
            Email = email,
            LeadSource = 'Self-Service Trial',
            Status = 'New'
        );

        insert lead;
        SyncGuard.inboundSyncIds.add(lead.Id);
    }
}
