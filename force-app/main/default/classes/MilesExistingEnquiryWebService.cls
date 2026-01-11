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
                
                // FIXED: Check list size
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


    // -------------------------
    // ✅ NEW: Notification for Lead Owner Change (Loss & Gain)
    // -------------------------
    public static void sendLeadOwnerChangeNotifications(List<Lead__c> leads, Map<Id, Lead__c> oldMap, String notificationDevName) {
        if (leads == null || leads.isEmpty() || oldMap == null) return;
        
        Id cnTypeId = getCustomNotificationTypeId(notificationDevName);
        if (cnTypeId == null) return;
        
        Map<Id, Integer> lostCount = new Map<Id, Integer>();
        Map<Id, Integer> gainedCount = new Map<Id, Integer>();
        Map<Id, Id> targetIds = new Map<Id, Id>(); 

        for (Lead__c l : leads) {
            Lead__c oldRec = oldMap.get(l.Id);
            if (oldRec != null && l.OwnerId != null && oldRec.OwnerId != l.OwnerId) {
                 // Lost Owner Logic
                if (oldRec.OwnerId != null) {
                    Integer c = lostCount.containsKey(oldRec.OwnerId) ? lostCount.get(oldRec.OwnerId) : 0;
                    lostCount.put(oldRec.OwnerId, c + 1);
                    if (!targetIds.containsKey(oldRec.OwnerId)) targetIds.put(oldRec.OwnerId, l.Id); 
                }
                // Gained Owner Logic
                if (l.OwnerId != null) {
                    Integer c = gainedCount.containsKey(l.OwnerId) ? gainedCount.get(l.OwnerId) : 0;
                    gainedCount.put(l.OwnerId, c + 1);
                    if (!targetIds.containsKey(l.OwnerId)) targetIds.put(l.OwnerId, l.Id);
                }
            }
        }
        
        // Send Lost Notifications
        for (Id uid : lostCount.keySet()) {
             sendSingleNotification(uid, targetIds.get(uid), cnTypeId, 'Lead Ownership Transferred', 'You have transferred ownership of ' + lostCount.get(uid) + ' lead(s).');
        }
        
        // Send Gained Notifications
        for (Id uid : gainedCount.keySet()) {
             sendSingleNotification(uid, targetIds.get(uid), cnTypeId, 'Lead Ownership Assigned', 'You have been assigned ownership of ' + gainedCount.get(uid) + ' lead(s).');
        }
    }

    private static void sendSingleNotification(Id userId, Id targetId, Id typeId, String title, String body) {
        Messaging.CustomNotification cn = new Messaging.CustomNotification();
        cn.setTitle(title);
        cn.setBody(body);
        cn.setNotificationTypeId(typeId);
        cn.setSenderId(UserInfo.getUserId());
        cn.setTargetId(targetId);
        try { 
            cn.send(new Set<String>{String.valueOf(userId)}); 
        } catch(Exception e) {
            System.debug('Notification Error: ' + e.getMessage());
        }
    }

}