public class CourseEnrolledTriggerHandler {
/*
    public static void afterUpdate(
        List<Course_Enrolled__c> newList,
        Map<Id, Course_Enrolled__c> oldMap
    ) {

        List<Task> tasksToInsert = new List<Task>();
        List<Task> tasksToUpdate = new List<Task>();

        Set<Id> courseIds = new Set<Id>();
        Set<String> stages = new Set<String>();

        
        for (Course_Enrolled__c ce : newList) {
            if (ce.Stages__c != oldMap.get(ce.Id).Stages__c) {
                courseIds.add(ce.Id);
                stages.add(ce.Stages__c);
                stages.add(oldMap.get(ce.Id).Stages__c);
            }
        }

        if (courseIds.isEmpty()) return;

     
        Map<String, Task_Manager__c> configByStage = new Map<String, Task_Manager__c>();
        for (Task_Manager__c cfg : [
            SELECT Stages__c,
                   Task_Name__c,
                   Follow_Up__c,
                   Max_Follow_up__c,
                   Owner__c
            FROM Task_Manager__c
            WHERE Stages__c IN :stages
        ]) {
            configByStage.put(cfg.Stages__c, cfg);
        }

      
        Map<Id, List<Task>> openTasksByCourse = new Map<Id, List<Task>>();

        for (Task t : [
            SELECT Id, Subject, Status, WhatId, OwnerId
            FROM Task
            WHERE WhatId IN :courseIds
            AND Status != 'Completed'
        ]) {
            if (!openTasksByCourse.containsKey(t.WhatId)) {
                openTasksByCourse.put(t.WhatId, new List<Task>());
            }
            openTasksByCourse.get(t.WhatId).add(t);
        }

       
        for (Course_Enrolled__c newRec : newList) {

            Course_Enrolled__c oldRec = oldMap.get(newRec.Id);
            if (newRec.Stages__c == oldRec.Stages__c) continue;

           
            Task_Manager__c oldCfg = configByStage.get(oldRec.Stages__c);
            if (oldCfg != null && openTasksByCourse.containsKey(newRec.Id)) {
                for (Task t : openTasksByCourse.get(newRec.Id)) {
                    if (t.Subject == oldCfg.Task_Name__c) {
                        t.Status = 'Completed';
                        tasksToUpdate.add(t);
                    }
                }
            }

         
            Task_Manager__c newCfg = configByStage.get(newRec.Stages__c);
            if (newCfg == null) continue;

            Task newTask = new Task();
            newTask.Subject = newCfg.Task_Name__c;
            newTask.WhatId = newRec.Id;
            newTask.Status = 'Not Started';
            newTask.Priority = 'High';
            newTask.Description = newCfg.Follow_Up__c;
            newTask.ActivityDate = calculateDueDate(newCfg.Max_Follow_up__c);

          
            if (newCfg.Owner__c == 'CC SPOC' && newRec.CC_Spoc__c != null) {
                newTask.OwnerId = newRec.CC_Spoc__c;
            } else {
                newTask.OwnerId = newRec.OwnerId;
            }

            tasksToInsert.add(newTask);
        }

      
        if (!tasksToUpdate.isEmpty()) update tasksToUpdate;
        if (!tasksToInsert.isEmpty()) insert tasksToInsert;
    }


    private static Date calculateDueDate(String maxFollowUp) {

        if (String.isBlank(maxFollowUp)) return Date.today();

        Integer days = 0;

        if (maxFollowUp.contains('Days')) {
            days = Integer.valueOf(maxFollowUp.replace(' Days', '').trim());
        } 
        else if (maxFollowUp.contains('Hours')) {
            days = 1;
        }

        return Date.today().addDays(days);
    } */
    
    public static void onAfterUpdate(Map<Id, Course_Enrolled__c> newMap, Map<Id, Course_Enrolled__c> oldMap) {
        
    }
}