public without sharing class LeadSearchController {

    // SEARCH LEAD BY PHONE
    @AuraEnabled(cacheable=true)
    public static List<Lead__c> searchLeadByPhone(String phoneNumber) {
        if (String.isBlank(phoneNumber)) {
            return new List<Lead__c>();
        }

        return [
            SELECT Id, Name, OwnerId, Phone__c, City__c, Course__c, Email__c, Stage__c
            FROM Lead__c
            WHERE Phone__c = :phoneNumber
            LIMIT 100
        ];
    }

    // SUBMIT APPROVAL BASED ON OWNER LOGIC
    @AuraEnabled
    public static String submitApproval(Id leadId) {

        // 1. Get selected Lead
        Lead__c selectedLead = [
            SELECT Id, OwnerId, Phone__c
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        // 2. Get all leads with same phone
        List<Lead__c> samePhoneLeads = [
            SELECT Id, OwnerId
            FROM Lead__c
            WHERE Phone__c = :selectedLead.Phone__c
        ];

        // 3. Check if owner is same or different
        Boolean isOwnerSame = true;
        for (Lead__c ld : samePhoneLeads) {
            if (ld.OwnerId != selectedLead.OwnerId) {
                isOwnerSame = false;
                break;
            }
        }

        // 4. Decide approver username based on logic
        // 👇 CHANGE THESE USERNAMES TO MATCH YOUR ORG USERS
        String gmUsername    = 'general.manager'; 
        String adminUsername = 'admin.user';

        String finalApprover = isOwnerSame ? gmUsername : adminUsername;

        // 5. Get User by Username (always available field)
        User approver = [
            SELECT Id, Username
            FROM User
            WHERE Username = :finalApprover
            LIMIT 1
        ];

        // 6. Submit Approval Request
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(leadId);
        req.setNextApproverIds(new Id[] { approver.Id });

        Approval.ProcessResult result = Approval.process(req);

        return 'Approval submitted to: ' + approver.Username;
    }
}