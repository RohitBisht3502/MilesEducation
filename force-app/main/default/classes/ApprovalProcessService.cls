/*
    Author       : Rohit Singh Bisht
*/
public without sharing class ApprovalProcessService {
    public static void processFinalizedRequests(List<Approval_Process__c> newList, Map<Id, Approval_Process__c> oldMap) {
        List<Approval_Process__c> approvedMerges = new List<Approval_Process__c>();
        List<Approval_Process__c> approvedTransfers = new List<Approval_Process__c>();
        List<Approval_Process__c> finalizedForNotification = new List<Approval_Process__c>();

        for (Approval_Process__c rec : newList) {
            Approval_Process__c oldRec = oldMap.get(rec.Id);
            if (rec.Merge_Status__c != oldRec.Merge_Status__c && (rec.Merge_Status__c == 'Approved' || rec.Merge_Status__c == 'Rejected')) {
                finalizedForNotification.add(rec);
                if (rec.Merge_Status__c == 'Approved') {
                    if (isLeadMergeRequest(rec.Record_Type__c)) {
                        approvedMerges.add(rec);
                    } else if (isLeadTransferRequest(rec.Record_Type__c)) {
                        approvedTransfers.add(rec);
                    }
                }
            }
        }

        if (!approvedMerges.isEmpty()) {
            executeLeadMerges(approvedMerges);
        }
        if (!approvedTransfers.isEmpty()) {
            executeLeadTransfers(approvedTransfers);
        }
        if (!finalizedForNotification.isEmpty()) {
            sendFinalDecisionNotifications(finalizedForNotification);
        }
        if (!finalizedForNotification.isEmpty()) {
            createFinalizationActivityLogs(finalizedForNotification);
        }
    }

    private static void executeLeadMerges(List<Approval_Process__c> records) {
        return;
    }

    private static void executeLeadTransfers(List<Approval_Process__c> records) {
        Set<Id> leadIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();

        for (Approval_Process__c rec : records) {
            if (rec.Master_Lead__c != null && rec.Requestor__c != null) {
                leadIds.add(rec.Master_Lead__c);
                userIds.add(rec.Requestor__c);
            }
        }

        if (leadIds.isEmpty()) return;

        Map<Id, Lead> leadMap = new Map<Id, Lead>([SELECT Id, OwnerId FROM Lead WHERE Id IN :leadIds]);
        for (Lead l : leadMap.values()) userIds.add(l.OwnerId);

        Map<Id, User> userMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :userIds]);

        List<Lead> leadsToUpdate = new List<Lead>();

        for (Approval_Process__c rec : records) {
            Lead ld = leadMap.get(rec.Master_Lead__c);
            if (ld == null) continue;

            User requestor = userMap.get(rec.Requestor__c);
            if (requestor != null) {
                ld.OwnerId = rec.Requestor__c;
            }
            leadsToUpdate.add(ld);
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }

    private static void sendFinalDecisionNotifications(List<Approval_Process__c> records) {
        for (Approval_Process__c ap : records) {
            String templateName;
            if (isLeadTransferRequest(ap.Record_Type__c)) {
                templateName = (ap.Merge_Status__c == 'Approved') ? 'Lead_Transfer_Approved' : 'Lead_Transfer_Rejected';
            } else {
                templateName = (ap.Merge_Status__c == 'Approved') ? 'Lead_Merge_Approved' : 'Lead_Merge_Rejected';
            }
            try {
                processAndSendSingleNotification(ap, templateName);
            } catch (Exception e) {
                System.debug('Notification failed: ' + e.getMessage());
            }
        }
    }

    private static void processAndSendSingleNotification(Approval_Process__c ap, String templateName) {
        User recipient = [SELECT Email FROM User WHERE Id = :ap.Requestor__c LIMIT 1];
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
        Id dummyWhoId = (ap.Source_Candidate__c != null) ? ap.Source_Candidate__c : (ap.Target_Candidate__c != null ? ap.Target_Candidate__c : ap.Master_Lead__c);

        if (!templates.isEmpty() && ap.Requestor__c != null && dummyWhoId != null) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(templates[0].Id);
            mail.setTargetObjectId(dummyWhoId);
            mail.setWhatId(ap.Id);
            mail.setTreatTargetObjectAsRecipient(false);
            mail.setToAddresses(new String[] { recipient.Email });
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } else if (String.isNotBlank(recipient.Email)) {
            Messaging.SingleEmailMessage plainMail = new Messaging.SingleEmailMessage();
            plainMail.setToAddresses(new String[] { recipient.Email });
            plainMail.setSubject((ap.Merge_Status__c == 'Approved' ? 'Approved: ' : 'Rejected: ') + (ap.Record_Type__c == null ? 'Approval Request' : ap.Record_Type__c));
            plainMail.setPlainTextBody('Your ' + (ap.Record_Type__c == null ? 'approval request' : ap.Record_Type__c) + ' has been ' + ap.Merge_Status__c.toLowerCase() + '.');
            plainMail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { plainMail });
        }

        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Custom_Notification' LIMIT 1];
        if (!types.isEmpty()) {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(types[0].Id);
            notification.setTargetId(ap.Id);
            String title = (ap.Merge_Status__c == 'Approved') ? 'Request Approved' : 'Request Rejected';
            String body = 'Your ' + (ap.Record_Type__c != null ? ap.Record_Type__c : 'approval') + ' request has been ' + ap.Merge_Status__c.toLowerCase() + '.';
            notification.setTitle(title);
            notification.setBody(body);
            notification.send(new Set<String>{String.valueOf(ap.Requestor__c)});
        }
    }

    private static void createFinalizationActivityLogs(List<Approval_Process__c> records) {
        List<Activity_log__c> logs = new List<Activity_log__c>();
        Set<Id> leadIds = new Set<Id>();
        for (Approval_Process__c rec : records) {
            if (isLeadTransferRequest(rec.Record_Type__c) && rec.Master_Lead__c != null) {
                leadIds.add(rec.Master_Lead__c);
            }
        }
        Map<Id, Lead> leadMap = new Map<Id, Lead>();
        if (!leadIds.isEmpty()) {
            leadMap = new Map<Id, Lead>([SELECT Id, OwnerId FROM Lead WHERE Id IN :leadIds]);
        }

        for (Approval_Process__c rec : records) {
            Activity_log__c log = new Activity_log__c(
                Logging_Id__c = rec.Id,
                Action_Performed_By__c = UserInfo.getUserId()
            );

            if (isLeadTransferRequest(rec.Record_Type__c)) {
                Lead ld = leadMap.get(rec.Master_Lead__c);
                log.Name = 'Candidate Transfer Decision';
                log.Candidate__c = rec.Master_Lead__c;
                log.Activity_Type__c = 'Owner Change';
                log.Description__c = 'Candidate Transfer Request ' + rec.Merge_Status__c + '. Decision Comments: ' + rec.Approval_Comments__c;
                log.Previous_Owner__c = (ld != null) ? ld.OwnerId : null;
                log.New_Owner__c = rec.Requestor__c;
            } else if (isLeadMergeRequest(rec.Record_Type__c)) {
                log.Name = 'Candidate Merge Decision';
                log.Candidate__c = rec.Target_Candidate__c;
                log.Activity_Type__c = 'Lead Merge';
                log.Description__c = 'Candidate Merge Request ' + rec.Merge_Status__c + '. Decision Comments: ' + rec.Approval_Comments__c;
            } else {
                continue;
            }
            logs.add(log);
        }
        if (!logs.isEmpty()) {
            ActivityLogService.insertLogs(logs);
        }
    }

    private static Boolean isLeadTransferRequest(String recordTypeValue) {
        return
            recordTypeValue == 'Lead Transfer' ||
            recordTypeValue == 'Lead Transfer Request' ||
            recordTypeValue == 'Candidate Transfer' ||
            recordTypeValue == 'Candidate Transfer Request';
    }

    private static Boolean isLeadMergeRequest(String recordTypeValue) {
        return
            recordTypeValue == 'Lead Merge' ||
            recordTypeValue == 'Lead Merged Request' ||
            recordTypeValue == 'Candidate Merge' ||
            recordTypeValue == 'Candidate Merged Request';
    }
}