/*
    Author       : Rohit Singh Bisht
*/
public without sharing class EligibilityFileTriggerHelperClass {
    public static void handleEligibilityFileStatusChange(Map<Id, Eligibility_File__c> oldMap, Map<Id, Eligibility_File__c> newMap) {
        List<Activity_log__c> activitiesToInsert = new List<Activity_log__c>();
        
        for (Id fileId : newMap.keySet()) {
            Eligibility_File__c oldFile = oldMap.get(fileId);
            Eligibility_File__c newFile = newMap.get(fileId);
            
            // Check if Status__c has changed
            if (oldFile.Status__c != newFile.Status__c && newFile.Candidate__c != null) {
                Activity_log__c activity = createActivityLog(
                    newFile.Name,
                    newFile.Candidate__c,
                    'Eligibility File Status',
                    oldFile.Status__c,
                    newFile.Status__c,
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
    
    private static Activity_log__c createActivityLog(String EligibilityFileName, Id candidateId, String fieldName, String oldValue, 
                                                      String newValue, Id ownerId, Id gpUserId, DateTime changedDateTime) {
        Lead Can = [SELECT Id, Name FROM Lead WHERE Id = :candidateId LIMIT 1];
        
        Activity_log__c activity = new Activity_log__c();
        activity.Name = 'Eligibility File of '+Can.Name;
        activity.Candidate__c = candidateId;
        activity.Logging_Id__c = candidateId;
        activity.Eligibility_File_Name__c = EligibilityFileName;
        activity.Activity_Type__c = 'Eligibility';
        activity.Previous_Level__c = oldValue;
        activity.New_Level__c = newValue;
        activity.Changed_Date_Time__c = changedDateTime;
        activity.Description__c = fieldName + ' changed from "' + oldValue + '" to "' + newValue + '"';
        
        return activity;
    }
    
    public static void handleEligibilityFileStatusChangeForStudent(Map<Id, Eligibility_File__c> oldMap, Map<Id, Eligibility_File__c> newMap) {
        List<Activity_log__c> activitiesToInsert = new List<Activity_log__c>();
        
        for (Id fileId : newMap.keySet()) {
            Eligibility_File__c oldFile = oldMap.get(fileId);
            Eligibility_File__c newFile = newMap.get(fileId);
            
            // Check if Status__c has changed
            if (oldFile.Status__c != newFile.Status__c && newFile.Student__c != null) {
                Activity_log__c activity = createActivityLogForStudent(
                    newFile.Name,
                    newFile.Student__c,
                    'Eligibility File Status',
                    oldFile.Status__c,
                    newFile.Status__c,
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
    
    private static Activity_log__c createActivityLogForStudent(String EligibilityFileName, Id studentId, String fieldName, String oldValue, 
                                                      String newValue, Id ownerId, Id gpUserId, DateTime changedDateTime) {
        Account Acc = [SELECT Id, Name FROM Account WHERE Id = :studentId LIMIT 1];
        
        Activity_log__c activity = new Activity_log__c();
        activity.Name = 'Eligibility File of '+Acc.Name;
        activity.Student__c = studentId;
        activity.Logging_Id__c = studentId;
        activity.Eligibility_File_Name__c = EligibilityFileName;
        activity.Activity_Type__c = 'Eligibility';
        activity.Previous_Level__c = oldValue;
        activity.New_Level__c = newValue;
        activity.Changed_Date_Time__c = changedDateTime;
        activity.Description__c = fieldName + ' changed from "' + oldValue + '" to "' + newValue + '"';
        
        return activity;
    }
}
