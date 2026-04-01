/*
    Author       : Rohit Singh Bisht
*/
public without sharing class EligibilityFolderTriggerHelperClass {
    public static void handleEligibilityFolderStatusChange(Map<Id, Eligibility_Folder__c> oldMap, Map<Id, Eligibility_Folder__c> newMap) {
        List<Activity_log__c> activitiesToInsert = new List<Activity_log__c>();
        
        for (Id folderId : newMap.keySet()) {
            Eligibility_Folder__c oldFolder = oldMap.get(folderId);
            Eligibility_Folder__c newFolder = newMap.get(folderId);
            
            // Check if Status__c has changed
            if (oldFolder.Status__c != newFolder.Status__c && newFolder.Candidate__c != null) {
                Activity_log__c activity = createActivityLog(
                    newFolder.Name,
                    newFolder.Candidate__c,
                    'Eligibility Folder Status',
                    oldFolder.Status__c,
                    newFolder.Status__c,
                    null, // Owner will be fetched from Candidate
                    null, // GP User will be fetched from Candidate
                    System.now()
                );
                activitiesToInsert.add(activity);
            }
        }
        
        // Insert all activity records
        if (!activitiesToInsert.isEmpty()) {
            ActivityLogService.insertLogs(activitiesToInsert);
        }
    }
    
    private static Activity_log__c createActivityLog(String EligibilityFolderName, Id candidateId, String fieldName, String oldValue, 
                                                      String newValue, Id ownerId, Id gpUserId, DateTime changedDateTime) {
        Lead Can = [SELECT Id, Name FROM Lead WHERE Id = :candidateId LIMIT 1];
        
        Activity_log__c activity = new Activity_log__c();
        activity.Name = 'Eligibility Folder of '+Can.Name;
        activity.Candidate__c = candidateId;
        activity.Logging_Id__c = candidateId;
        activity.Eligibility_Folder_Name__c = EligibilityFolderName;
        activity.Activity_Type__c = 'Eligibility';
        activity.Previous_Level__c = oldValue;
        activity.New_Level__c = newValue;
        activity.Changed_Date_Time__c = changedDateTime;
        activity.Description__c = fieldName + ' changed from "' + oldValue + '" to "' + newValue + '"';
        
        return activity;
    }
    
    public static void handleEligibilityFolderStatusChangeForStudent(Map<Id, Eligibility_Folder__c> oldMap, Map<Id, Eligibility_Folder__c> newMap) {
        List<Activity_log__c> activitiesToInsert = new List<Activity_log__c>();
        
        for (Id folderId : newMap.keySet()) {
            Eligibility_Folder__c oldFolder = oldMap.get(folderId);
            Eligibility_Folder__c newFolder = newMap.get(folderId);
            
            // Check if Status__c has changed
            if (oldFolder.Status__c != newFolder.Status__c && newFolder.Student__c != null) {
                Activity_log__c activity = createActivityLogForStudent(
                    newFolder.Name,
                    newFolder.Student__c,
                    'Eligibility Folder Status',
                    oldFolder.Status__c,
                    newFolder.Status__c,
                    null, // Owner will be fetched from Student
                    null, // GP User will be fetched from Student
                    System.now()
                );
                activitiesToInsert.add(activity);
            }
        }
        
        // Insert all activity records
        if (!activitiesToInsert.isEmpty()) {
            ActivityLogService.insertLogs(activitiesToInsert);
        }
    }
    
    private static Activity_log__c createActivityLogForStudent(String EligibilityFolderName, Id studentId, String fieldName, String oldValue, 
                                                      String newValue, Id ownerId, Id gpUserId, DateTime changedDateTime) {
        Account Acc = [SELECT Id, Name FROM Account WHERE Id = :studentId LIMIT 1];
        
        Activity_log__c activity = new Activity_log__c();
        activity.Name = 'Eligibility Folder of '+Acc.Name;
        activity.Student__c = studentId;
        activity.Logging_Id__c = studentId;
        activity.Eligibility_Folder_Name__c = EligibilityFolderName;
        activity.Activity_Type__c = 'Eligibility';
        activity.Previous_Level__c = oldValue;
        activity.New_Level__c = newValue;
        activity.Changed_Date_Time__c = changedDateTime;
        activity.Description__c = fieldName + ' changed from "' + oldValue + '" to "' + newValue + '"';
        
        return activity;
    }
}