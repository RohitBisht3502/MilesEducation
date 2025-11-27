public without sharing class EnquiryTriggerHandler {

    public static void handleReEnquiryUpgrade(List<Enquiry__c> newEnquiries) {

        Map<String, Enquiry__c> keyToEnquiry = new Map<String, Enquiry__c>();
        Set<String> phones = new Set<String>();
        Set<String> courses = new Set<String>();

        for (Enquiry__c e : newEnquiries) {
            if (e.Phone_Number__c != null && e.Course__c != null) {
                String key = e.Phone_Number__c + '||' + e.Course__c;
                keyToEnquiry.put(key, e);

                phones.add(e.Phone_Number__c);
                courses.add(e.Course__c);
            }
        }

        // FIXED: Include M1, M2, M3
        List<Lead__c> leads = [
            SELECT Id, Phone__c, Course__c, Stage__c, OwnerId
            FROM Lead__c
            WHERE Stage__c IN ('M1','M2','M3')
            AND Phone__c IN :phones
            AND Course__c IN :courses
        ];

        if (leads.isEmpty()) return;

        Map<Id, Call_Log__c> leadToConnectedCall = new Map<Id, Call_Log__c>();

        List<Call_Log__c> connectedLogs = [
            SELECT Id, Lead__c, Status__c, Called_By__c, Created_At__c, L1__c
            FROM Call_Log__c
            WHERE Lead__c IN :leads
            AND L1__c = 'Connected'
            ORDER BY Created_At__c DESC
        ];

        for (Call_Log__c log :connectedLogs) {
            if (!leadToConnectedCall.containsKey(log.Lead__c)) {
                leadToConnectedCall.put(log.Lead__c, log);
            }
        }

        List<Lead__c> leadsToUpdate = new List<Lead__c>();

        for (Lead__c lead : leads) {

            String key = lead.Phone__c + '||' + lead.Course__c;

            if (!keyToEnquiry.containsKey(key)) continue;

            Boolean shouldUpgrade = false;

            // Scenario B
            if (shouldUpgradeScenarioB(lead)) {
                shouldUpgrade = true;
            }

            // Scenario A — connected call
            if (!shouldUpgrade && leadToConnectedCall.containsKey(lead.Id)) {
                Call_Log__c cl = leadToConnectedCall.get(lead.Id);
                if (cl.Called_By__c == lead.OwnerId) {
                    shouldUpgrade = true;
                }
            }

            // Scenario A — no connected call + next day re-enquiry
            if (!shouldUpgrade) {
                Boolean noConnected = !leadToConnectedCall.containsKey(lead.Id);
                if (noConnected) {
                    Enquiry__c req = keyToEnquiry.get(key);
                    if (Date.today().daysBetween(req.CreatedDate.date()) != 0) {
                        shouldUpgrade = true;
                    }
                }
            }

            if (shouldUpgrade) {
                lead.Stage__c = 'M3+';
                leadsToUpdate.add(lead);
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }

    private static Boolean shouldUpgradeScenarioB(Lead__c lead) {
        return lead.Stage__c == 'M1' || lead.Stage__c == 'M2';
    }
}