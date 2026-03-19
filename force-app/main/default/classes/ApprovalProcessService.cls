public class ApprovalProcessService {

    /**
     * Entry point for handling finalized approvals/rejections from Trigger
     */
    public static void processFinalizedRequests(List<Approval_Process__c> newList, Map<Id, Approval_Process__c> oldMap) {
        
        List<Approval_Process__c> approvedMerges = new List<Approval_Process__c>();
        List<Approval_Process__c> approvedTransfers = new List<Approval_Process__c>();
        List<Approval_Process__c> finalizedForNotification = new List<Approval_Process__c>();

        for (Approval_Process__c rec : newList) {
            Approval_Process__c oldRec = oldMap.get(rec.Id);

            // Check for status change to Approved or Rejected
            if (rec.Merge_Status__c != oldRec.Merge_Status__c && 
                (rec.Merge_Status__c == 'Approved' || rec.Merge_Status__c == 'Rejected')) {
                
                finalizedForNotification.add(rec);

                if (rec.Merge_Status__c == 'Approved') {
                    if (rec.Record_Type__c == 'Lead Merge') {
                        approvedMerges.add(rec);
                    } else if (rec.Record_Type__c == 'Lead Transfer') {
                        approvedTransfers.add(rec);
                    }
                }
            }
        }

        // 1. Execute Lead Merges
        if (!approvedMerges.isEmpty()) {
            executeLeadMerges(approvedMerges);
        }

        // 2. Execute Lead Transfers
        if (!approvedTransfers.isEmpty()) {
            executeLeadTransfers(approvedTransfers);
        }

        // 3. Send Notifications
        if (!finalizedForNotification.isEmpty()) {
            sendFinalDecisionNotifications(finalizedForNotification);
        }

        // 4. Create Activity Logs for Decisions
        if (!finalizedForNotification.isEmpty()) {
            createFinalizationActivityLogs(finalizedForNotification);
        }
    }

    private static void executeLeadMerges(List<Approval_Process__c> records) {
        List<Lead> leadsToUpdate = new List<Lead>();
        
        for (Approval_Process__c ap : records) {
            if (ap.Source_Candidate__c != null && ap.Target_Candidate__c != null) {
                // Mark source as merged
                leadsToUpdate.add(new Lead(
                    Id = ap.Source_Candidate__c,
                    Candidate__c = ap.Target_Candidate__c,
                    Is_Merged__c = true
                ));

                // Add comments to target
                leadsToUpdate.add(new Lead(
                    Id = ap.Target_Candidate__c,
                    Merge_Comments__c = ap.Approval_Comments__c
                ));
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
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
            if (ap.Record_Type__c == 'Lead Transfer') {
                templateName = (ap.Merge_Status__c == 'Approved') ? 'Lead_Transfer_Approved' : 'Lead_Transfer_Rejected';
            } else {
                templateName = (ap.Merge_Status__c == 'Approved') ? 'Lead_Merge_Approved' : 'Lead_Merge_Rejected';
            }
            
            // Reusing existing notification logic (wrapped in a try-catch for safety)
            try {
                processAndSendSingleNotification(ap, templateName);
            } catch (Exception e) {
                System.debug('Notification failed: ' + e.getMessage());
            }
        }
    }

    private static void processAndSendSingleNotification(Approval_Process__c ap, String templateName) {
        User recipient = [SELECT Email FROM User WHERE Id = :ap.Requestor__c LIMIT 1];
        
        // 1. Send Email
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
        if (!templates.isEmpty() && ap.Requestor__c != null) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(templates[0].Id);
            
            // Logic to find a valid TargetObjectId (Lead) for merge fields
            Id dummyWhoId = (ap.Source_Candidate__c != null) ? ap.Source_Candidate__c : 
                            (ap.Target_Candidate__c != null ? ap.Target_Candidate__c : ap.Master_Lead__c);
            
            if (dummyWhoId != null) {
                mail.setTargetObjectId(dummyWhoId); 
                mail.setWhatId(ap.Id);
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new String[] { recipient.Email });
                mail.setSaveAsActivity(false);
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            }
        }

        // 2. Push Notification
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Lead_Merge_Status_Notification' LIMIT 1];
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
            if (rec.Record_Type__c == 'Lead Transfer' && rec.Master_Lead__c != null) {
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

            if (rec.Record_Type__c == 'Lead Transfer') {
                Lead ld = leadMap.get(rec.Master_Lead__c);
                log.Name = 'Lead Transfer Decision';
                log.Candidate__c = rec.Master_Lead__c;
                log.Activity_Type__c = 'Owner Change';
                log.Description__c = 'Lead Transfer Request ' + rec.Merge_Status__c + '. Decision Comments: ' + rec.Approval_Comments__c;
                log.Previous_Owner__c = (ld != null) ? ld.OwnerId : null;
                log.New_Owner__c = rec.Requestor__c;
            } else if (rec.Record_Type__c == 'Lead Merge') {
                log.Name = 'Lead Merge Decision';
                log.Candidate__c = rec.Target_Candidate__c;
                log.Activity_Type__c = 'Lead Merge';
                log.Description__c = 'Lead Merge Request ' + rec.Merge_Status__c + '. Decision Comments: ' + rec.Approval_Comments__c;
            } else {
                continue;
            }
            logs.add(log);
        }
        
        if (!logs.isEmpty()) {
            insert logs;
        }
    }
}