public with sharing class LeadMergeApprovalDecisionController {

    @AuraEnabled
    public static void processApprovalResult(Id approvalId, String status, String managerComments) {
        if (String.isBlank(managerComments)) {
            throw new AuraHandledException('Comments are mandatory for finalizing the approval.');
        }
        if (approvalId == null) {
            throw new AuraHandledException('Approval Id is required.');
        }

        Approval_Process__c approvalRecord = [SELECT Id, Source_Candidate__c, Target_Candidate__c, Merge_Status__c, Approval_Comments__c, Requestor__c, Record_Type__c FROM Approval_Process__c WHERE Id = :approvalId LIMIT 1];
        if (
            approvalRecord.Record_Type__c != 'Lead Merged Request' &&
            approvalRecord.Record_Type__c != 'Candidate Merged Request' &&
            approvalRecord.Record_Type__c != 'Lead Merge' &&
            approvalRecord.Record_Type__c != 'Candidate Merge'
        ) {
            throw new AuraHandledException('This action is only supported for candidate merge approvals.');
        }

        approvalRecord.Merge_Status__c = status;
        approvalRecord.Approval_Comments__c = managerComments;
        update approvalRecord;

        if (status == 'Approved' && approvalRecord.Source_Candidate__c != null && approvalRecord.Target_Candidate__c != null) {
            CandidateMergeService.mergeCandidates(
                approvalRecord.Source_Candidate__c,
                approvalRecord.Target_Candidate__c,
                managerComments
            );
        }
    }

    public static void sendNotifications(Id processId, Id targetUserId, String templateDeveloperName) {
        if (targetUserId == null || processId == null) {
            return;
        }

        try {
            User recipient = [SELECT Email FROM User WHERE Id = :targetUserId LIMIT 1];
            Approval_Process__c approvalRecord = [SELECT Source_Candidate__c, Target_Candidate__c FROM Approval_Process__c WHERE Id = :processId LIMIT 1];
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateDeveloperName LIMIT 1];
            Id dummyWhoId = approvalRecord.Source_Candidate__c != null ? approvalRecord.Source_Candidate__c : approvalRecord.Target_Candidate__c;

            if (!templates.isEmpty() && dummyWhoId != null && String.isNotBlank(recipient.Email)) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templates[0].Id);
                mail.setTargetObjectId(dummyWhoId);
                mail.setWhatId(processId);
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new String[] { recipient.Email });
                mail.setSaveAsActivity(false);
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            } else if (String.isNotBlank(recipient.Email)) {
                Messaging.SingleEmailMessage plainMail = new Messaging.SingleEmailMessage();
                plainMail.setToAddresses(new String[] { recipient.Email });
                plainMail.setSubject(templateDeveloperName == 'Lead_Merge_Approval_Request' ? 'Candidate Merge Approval Request' : (templateDeveloperName == 'Lead_Merge_Approved' ? 'Candidate Merge Approved' : 'Candidate Merge Rejected'));
                plainMail.setPlainTextBody(templateDeveloperName == 'Lead_Merge_Approval_Request' ? 'A new candidate merge request requires your approval.' : (templateDeveloperName == 'Lead_Merge_Approved' ? 'Your candidate merge request has been approved.' : 'Your candidate merge request has been rejected.'));
                plainMail.setSaveAsActivity(false);
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { plainMail });
            }

            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Custom_Notification' LIMIT 1];
            if (!types.isEmpty()) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(types[0].Id);
                notification.setTargetId(processId);
                notification.setTitle(templateDeveloperName == 'Lead_Merge_Approval_Request' ? 'Merge Request Pending' : (templateDeveloperName == 'Lead_Merge_Approved' ? 'Merge Request Approved' : 'Merge Request Rejected'));
                notification.setBody(templateDeveloperName == 'Lead_Merge_Approval_Request' ? 'A new candidate merge request requires your approval.' : (templateDeveloperName == 'Lead_Merge_Approved' ? 'Your candidate merge request has been approved and finalized.' : 'Your candidate merge request has been rejected.'));
                notification.send(new Set<String>{ String.valueOf(targetUserId) });
            }
        } catch (Exception e) {
            System.debug('LeadMergeApprovalDecisionController notification failed: ' + e.getMessage());
            if (e.getMessage().contains('INVALID_ID_FIELD')) {
                throw new AuraHandledException('Email Configuration Error: ' + e.getMessage());
            }
        }
    }
}