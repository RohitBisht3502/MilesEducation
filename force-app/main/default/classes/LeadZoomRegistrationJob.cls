public class LeadZoomRegistrationJob implements Queueable, Database.AllowsCallouts {

    private Set<Id> leadIds;

    public LeadZoomRegistrationJob(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext qc) {
        System.debug('🚀 [LeadZoomRegistrationJob] Started for Leads: ' + leadIds);

        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Email, Phone, City__c
            FROM Lead
            WHERE Id IN :leadIds
        ];

        if (leads.isEmpty()) {
            System.debug('⚠️ No Leads found for IDs: ' + leadIds);
            return;
        }

        try {
            // Step 1: Generate Access Token
            System.debug('🔐 Generating Zoom Access Token...');
            String token = ZoomIntegrationService.generateZoomAccessToken();
            System.debug('✅ Token generated successfully.');

            // Step 2: Register each Lead for webinar
            List<Integration_Log__c> logs = new List<Integration_Log__c>();

            for (Lead ld : leads) {
                System.debug('➡️ Registering Lead: ' + ld.Id + ' (' + ld.FirstName + ' - ' + ld.Phone + ')');

                if (String.isBlank(ld.City__c)) {
                    System.debug('⚠️ Skipping Lead ' + ld.Id + ' (City__c blank)');
                    continue;
                }

                try {
                    ZoomIntegrationService.registerLeadForWebinar(ld, token);

                    logs.add(IntegrationLogUtil.buildLog(
                        'Zoom Webinar Registration Job',
                        'LeadId: ' + ld.Id,
                        'Registered Successfully',
                        null,
                        'SUCCESS',
                        200
                    ));
                } catch (Exception innerEx) {
                    System.debug('❌ Failed to register Lead: ' + ld.Id + ' Error: ' + innerEx.getMessage());
                    logs.add(IntegrationLogUtil.buildLog(
                        'Zoom Webinar Registration Job',
                        'LeadId: ' + ld.Id,
                        null,
                        innerEx.getMessage(),
                        'FAILED',
                        null
                    ));
                }
            }

            if (!logs.isEmpty()) {
                IntegrationLogUtil.insertLogs(logs);
                System.debug('📝 Job-level Integration logs inserted successfully.');
            }

        } catch (Exception ex) {
            System.debug('🔥 [LeadZoomRegistrationJob] Error: ' + ex.getMessage());

            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                IntegrationLogUtil.buildLog(
                    'Zoom Integration Job Error',
                    JSON.serialize(leadIds),
                    null,
                    ex.getMessage(),
                    'FAILED',
                    null
                )
            });
        }

        System.debug('🏁 [LeadZoomRegistrationJob] Finished.');
    }
}