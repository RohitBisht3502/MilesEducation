global class LeadEscalationBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        DateTime cutoffTime = System.now().addHours(-24);

        return Database.getQueryLocator([
            SELECT Id, OwnerId, CreatedDate,
                   Next_Follow_Up_Date__c,
                   Owner.UserRoleId,
                   Owner.UserRole.DeveloperName,
                   Owner.UserRole.ParentRoleId
            FROM Lead__c
            WHERE CreatedDate <= :cutoffTime
              AND Next_Follow_Up_Date__c = NULL
              AND OwnerId IN (SELECT Id FROM User WHERE IsActive = true)
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Lead__c> scope) {

        Set<Id> parentRoleIds = new Set<Id>();
        Map<Id, Id> roleToParentRole = new Map<Id, Id>();

        // Step 1: Collect eligible roles
        for (Lead__c l : scope) {
            if (l.Owner.UserRole != null &&
                (l.Owner.UserRole.DeveloperName == 'CC' ||
                 l.Owner.UserRole.DeveloperName == 'SC' ||
                 l.Owner.UserRole.DeveloperName == 'SR')) {

                if (l.Owner.UserRole.ParentRoleId != null) {
                    roleToParentRole.put(
                        l.Owner.UserRoleId,
                        l.Owner.UserRole.ParentRoleId
                    );
                    parentRoleIds.add(l.Owner.UserRole.ParentRoleId);
                }
            }
        }

        if (parentRoleIds.isEmpty()) return;

        // Step 2: Get GM users
        Map<Id, User> roleIdToGMUser = new Map<Id, User>();

        for (User u : [
            SELECT Id, UserRoleId
            FROM User
            WHERE UserRoleId IN :parentRoleIds
              AND IsActive = true
        ]) {
            if (!roleIdToGMUser.containsKey(u.UserRoleId)) {
                roleIdToGMUser.put(u.UserRoleId, u);
            }
        }

        List<Lead__c> leadsToUpdate = new List<Lead__c>();
        List<Task> tasksToInsert = new List<Task>(); 

        for (Lead__c l : scope) {

            if (l.Owner.UserRole != null &&
                roleToParentRole.containsKey(l.Owner.UserRoleId)) {

                Id parentRoleId = roleToParentRole.get(l.Owner.UserRoleId);

                if (roleIdToGMUser.containsKey(parentRoleId)) {

                    User gmUser = roleIdToGMUser.get(parentRoleId);

                    //️⃣ Reassign Lead
                    l.OwnerId = gmUser.Id;
                    leadsToUpdate.add(l);

            // ️⃣ Create Task for GM
                    Task t = new Task();
                    t.OwnerId = gmUser.Id;
                    t.WhatId = l.Id; 
                    t.Subject = 'Lead Escalated – No Follow-Up in 24 Hours';
                    t.Status = 'Not Started';
                    t.Priority = 'High';
                    t.ActivityDate = Date.today();

                    t.Description =
                        'Lead was created on ' + l.CreatedDate.format() +
                        '. No Next Follow-Up Date was set within 24 hours by the previous owner.' +
                        ' Hence, this lead has been escalated to you.';

                    tasksToInsert.add(t);
                }
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Lead Escalation Batch Finished');
    }
}