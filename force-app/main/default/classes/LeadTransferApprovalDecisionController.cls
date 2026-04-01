/**
 * Author: ROhit SINGH BISHT
 */
public without sharing class LeadTransferApprovalDecisionController {

    @AuraEnabled
    public static void processApprovalResult(Id approvalId, String status, String managerComments) {
        if (String.isBlank(managerComments)) {
            throw new AuraHandledException('Comments are mandatory for finalized decisions.');
        }
        if (approvalId == null) {
            throw new AuraHandledException('Approval Id is required.');
        }
        if (status != 'Approved' && status != 'Rejected') {
            throw new AuraHandledException('Invalid approval status.');
        }

        Approval_Process__c approvalRecord = [SELECT Id, Record_Type__c, Merge_Status__c, Master_Lead__c, Requestor__c FROM Approval_Process__c WHERE Id = :approvalId LIMIT 1];

        if (
            approvalRecord.Record_Type__c != 'Lead Transfer Request' &&
            approvalRecord.Record_Type__c != 'Candidate Transfer Request' &&
            approvalRecord.Record_Type__c != 'Lead Transfer' &&
            approvalRecord.Record_Type__c != 'Candidate Transfer'
        ) {
            throw new AuraHandledException('This action is only supported for candidate transfer approvals.');
        }

        approvalRecord.Merge_Status__c = status;
        approvalRecord.Approval_Comments__c = managerComments;
        update approvalRecord;

        if (status == 'Approved' && approvalRecord.Master_Lead__c != null && approvalRecord.Requestor__c != null) {
            Lead candidateLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :approvalRecord.Master_Lead__c LIMIT 1];

            if (candidateLead.OwnerId != approvalRecord.Requestor__c) {
                Map<Id, Lead> oldLeadMap = new Map<Id, Lead>{
                    candidateLead.Id => candidateLead.clone(true, true, true, true)
                };

                candidateLead.OwnerId = approvalRecord.Requestor__c;
                update candidateLead;

                LeadRelatedSyncService.syncRelatedLeadsOnCandidateOwnerChange(
                    new List<Lead>{ candidateLead },
                    oldLeadMap
                );
            }
        }

        sendNotifications(approvalRecord.Id, approvalRecord.Requestor__c, status);
    }

    public static void sendNotifications(Id processId, Id targetUserId, String status) {
        if (targetUserId == null || processId == null) {
            return;
        }

        try {
            String templateDeveloperName = status == 'Approved' ? 'Lead_Transfer_Approved' : 'Lead_Transfer_Rejected';
            String emailSubject = status == 'Approved' ? 'Candidate Transfer Approved' : 'Candidate Transfer Rejected';
            String emailBody = status == 'Approved'
                ? 'Your candidate transfer request has been approved.'
                : 'Your candidate transfer request has been rejected.';
            String notificationTitle = status == 'Approved' ? 'Transfer Request Approved' : 'Transfer Request Rejected';
            String notificationBody = status == 'Approved'
                ? 'Your candidate transfer request has been approved and finalized.'
                : 'Your candidate transfer request has been rejected.';

            User recipient = [SELECT Email FROM User WHERE Id = :targetUserId LIMIT 1];
            Approval_Process__c approvalRecord = [SELECT Master_Lead__c FROM Approval_Process__c WHERE Id = :processId LIMIT 1];
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateDeveloperName LIMIT 1];

            if (!templates.isEmpty() && approvalRecord.Master_Lead__c != null && String.isNotBlank(recipient.Email)) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templates[0].Id);
                mail.setTargetObjectId(approvalRecord.Master_Lead__c);
                mail.setWhatId(processId);
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new String[] { recipient.Email });
                mail.setSaveAsActivity(false);
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            } else if (String.isNotBlank(recipient.Email)) {
                Messaging.SingleEmailMessage plainMail = new Messaging.SingleEmailMessage();
                plainMail.setToAddresses(new String[] { recipient.Email });
                plainMail.setSubject(emailSubject);
                plainMail.setPlainTextBody(emailBody);
                plainMail.setSaveAsActivity(false);
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { plainMail });
            }

            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Custom_Notification' LIMIT 1];
            if (!types.isEmpty()) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(types[0].Id);
                notification.setTargetId(processId);
                notification.setTitle(notificationTitle);
                notification.setBody(notificationBody);
                notification.send(new Set<String>{ String.valueOf(targetUserId) });
            }
        } catch (Exception e) {
            System.debug('LeadTransferApprovalDecisionController notification failed: ' + e.getMessage());
            if (e.getMessage().contains('INVALID_ID_FIELD')) {
                throw new AuraHandledException('Email Configuration Error: ' + e.getMessage());
            }
        }
    }
}