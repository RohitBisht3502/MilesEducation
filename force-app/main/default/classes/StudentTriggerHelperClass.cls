/*
    Author       : Rohit Singh Bisht
*/
public without sharing class StudentTriggerHelperClass {
    public static void handleStudentStatusChange(Map<Id, Account> newMap, Map<Id, Account> oldMap) {
        List<Activity_log__c> activitiesToInsert = new List<Activity_log__c>();
        
        for (Id studentId : newMap.keySet()) {
            Account oldStudent = oldMap.get(studentId);
            Account newStudent = newMap.get(studentId);
            
            // Check if GP_Lead_Status__c has changed
            if (oldStudent.GP_Lead_Status__c != newStudent.GP_Lead_Status__c) {
                Activity_log__c activity = createActivityLog(
                    studentId,
                    'GP_Lead_Status__c',
                    oldStudent.GP_Lead_Status__c,
                    newStudent.GP_Lead_Status__c,
                    newStudent.OwnerId,
                    newStudent.GP_User__c,
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
    
    private static Activity_log__c createActivityLog(Id studentId, String fieldName, String oldValue, 
                                                      String newValue, Id ownerId, Id gpUserId, DateTime changedDateTime) {
        Account Acc = [SELECT Id, Name FROM Account WHERE Id = :studentId LIMIT 1];
        
        Activity_log__c activity = new Activity_log__c();
        activity.Name = 'Eligibility Information of ' + Acc.Name;
        activity.Student__c = studentId;
        activity.Logging_Id__c = studentId;
        activity.Activity_Type__c = 'Eligibility';
        activity.Previous_Level__c = oldValue;
        activity.New_Level__c = newValue;
        activity.Changed_Date_Time__c = changedDateTime;
        activity.Description__c = fieldName + ' changed from "' + oldValue + '" to "' + newValue + '"';
        
        return activity;
    }
}
