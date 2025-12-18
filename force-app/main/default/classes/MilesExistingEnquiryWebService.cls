/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class MilesExistingEnquiryWebService {

    public static Task createFollowUpTask(Enquiry__c enquiryRecord, String subject) {
        return createFollowUpTask((SObject)enquiryRecord, subject, null);
    }

    public static Task createFollowUpTask(SObject whatRecord, String subject, Id ownerId) {
        // Minimal fix: proper guard
        if (whatRecord == null && String.isBlank(subject) && ownerId == null) {
            return null;
        }

        Task t = new Task(
            WhatId      = (whatRecord != null ? whatRecord.Id : null),
            OwnerId     = (ownerId != null ? ownerId : UserInfo.getUserId()),
            Subject     = String.isBlank(subject) ? 'Follow Up Call' : subject,
            Priority    = 'Normal',
            Status      = 'Open',
            Type        = 'Task Assigned To',
            Description = 'Auto-created task for SPOC follow-up via Miles API.'
        );
        insert t;

        // Existing behavior
        sendTaskAssignedNotification(t, 'Custom_Notification');
        return t;
    }

    // -------------------------
    // Existing: Single task notification
    // -------------------------
    public static void sendTaskAssignedNotification(Task t, String notificationDevName) {
        if (t == null || t.OwnerId == null || String.isBlank(notificationDevName)) return;

        try {
            Id cnTypeId = getCustomNotificationTypeId(notificationDevName);
            if (cnTypeId == null) return;

            Set<String> userIds = new Set<String>{ String.valueOf(t.OwnerId) };

            Messaging.CustomNotification cn = new Messaging.CustomNotification();
            cn.setBody('A new task has been assigned to you: ' + (t.Subject == null ? 'Task' : t.Subject));
            cn.setTitle('New Task Assigned');
            cn.setNotificationTypeId(cnTypeId);
            cn.setSenderId(UserInfo.getUserId());
            cn.setTargetId(t.Id);
            cn.send(userIds);

        } catch (Exception ex) {
            System.debug('Custom notification failed: ' + ex.getMessage());
        }
    }

    // -------------------------
    // ✅ NEW: Bulk notification (ONE notification per owner)
    // -------------------------
    public static void sendTaskAssignedNotificationBulk(List<Task> tasks, String notificationDevName) {
        if (tasks == null || tasks.isEmpty() || String.isBlank(notificationDevName)) return;

        // Group by owner
        Map<Id, List<Task>> ownerToTasks = new Map<Id, List<Task>>();
        for (Task t : tasks) {
            if (t == null || t.OwnerId == null) continue;
            if (!ownerToTasks.containsKey(t.OwnerId)) ownerToTasks.put(t.OwnerId, new List<Task>());
            ownerToTasks.get(t.OwnerId).add(t);
        }
        if (ownerToTasks.isEmpty()) return;

        try {
            Id cnTypeId = getCustomNotificationTypeId(notificationDevName);
            if (cnTypeId == null) return;

            // One notification per owner
            for (Id ownerId : ownerToTasks.keySet()) {
                List<Task> ownerTasks = ownerToTasks.get(ownerId);
                if (ownerTasks == null || ownerTasks.isEmpty()) continue;

                Integer cnt = ownerTasks.size();
                Task targetTask = ownerTasks[0]; // target must be ONE record

                Set<String> userIds = new Set<String>{ String.valueOf(ownerId) };

                Messaging.CustomNotification cn = new Messaging.CustomNotification();
                cn.setTitle('New Tasks Assigned');
                cn.setBody('You have been assigned ' + String.valueOf(cnt) + ' new task(s).');
                cn.setNotificationTypeId(cnTypeId);
                cn.setSenderId(UserInfo.getUserId());
                cn.setTargetId(targetTask.Id);
                cn.send(userIds);
            }

        } catch (Exception ex) {
            System.debug('Bulk custom notification failed: ' + ex.getMessage());
        }
    }

    // -------------------------
    // Helper (fetch once per call)
    // -------------------------
    private static Id getCustomNotificationTypeId(String developerName) {
        if (String.isBlank(developerName)) return null;
        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
}