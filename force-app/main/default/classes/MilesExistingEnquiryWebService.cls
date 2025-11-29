/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class MilesExistingEnquiryWebService {

    public static Task createFollowUpTask(Enquiry__c enquiryRecord, String subject) {
        if (enquiryRecord == null) {
            throw new AuraHandledException('Enquiry record cannot be null.');
        }

        Task t = new Task(
            WhatId = enquiryRecord.Id,
            Subject = String.isBlank(subject) ? 'Follow Up Call' : subject,
            Priority = 'Normal',
            Status = 'Open',
            Type = 'Task Assigned To',
            Description = 'Auto-created task for SPOC follow-up via Miles API.'
        );
        insert t;

       // sendTaskAssignedNotification(t, 'Custom_Notification');
        return t;
    }

    public static void sendTaskAssignedNotification(Task t, String notificationDevName) {
        System.debug(t);
        if (t == null || t.OwnerId == null || String.isBlank(notificationDevName)) return;
        try {
            Set<String> userIds = new Set<String>{ String.valueOf(t.OwnerId) };
            System.debug(userIds);
            CustomNotificationType cnType = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :notificationDevName
                LIMIT 1
            ];

            Messaging.CustomNotification cn = new Messaging.CustomNotification();
            cn.setBody('A new task has been assigned to you: ' + (t.Subject == null ? 'Task' : t.Subject));
            cn.setTitle('New Task Assigned');
            cn.setNotificationTypeId(cnType.Id);
            cn.setSenderId(UserInfo.getUserId());
            cn.setTargetId(t.Id);
            cn.send(userIds);

        } catch (Exception ex) {
            System.debug('Custom notification failed: ' + ex.getMessage());
        }
    }
}