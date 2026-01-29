public class CourseEnrolledTriggerHandlerService {

    public static void checkAndCreateNewTaskForStatusChange(Map<Id, Course_Enrolled__c> newMap, Map<Id, Course_Enrolled__c> oldMap) {
        List<Course_Enrolled__c> cpaStatusChangedList 	= new List<Course_Enrolled__c>();
        List<Course_Enrolled__c> cmaStatusChangedList 	= new List<Course_Enrolled__c>();
        
        for(Course_Enrolled__c enrolledObj : newMap.values()) {
            if(enrolledObj.Stages__c != oldMap.get(enrolledObj.Id).Stages__c) {
                if(enrolledObj.Course__c == 'CPA') cpaStatusChangedList.add(enrolledObj);
                if(enrolledObj.Course__c == 'CMA') cmaStatusChangedList.add(enrolledObj);   
            }
        }
        
        if(!cpaStatusChangedList.isEmpty()) createCPATasks(cpaStatusChangedList, oldMap);
        if(!cmaStatusChangedList.isEmpty()) createCPATasks(cpaStatusChangedList, oldMap);
    }
    
    
    static void createCPATasks(List<Course_Enrolled__c> cpaStatusChangedList, Map<Id, Course_Enrolled__c> oldMap) {
        List<Task> taskList = new List<Task>();
        String subjectName;
        for(Course_Enrolled__c enrolledObj : cpaStatusChangedList) {
            if(enrolledObj.Stages__c == 'M7+') taskList.add(createTask('Complete Onboarding', enrolledObj.Id, 0, enrolledObj.OwnerId));
//            if(enrolledObj.Stages__c == 'M7#') taskList.add(createTask('Upload docs for Evaluation advice', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M7#-') taskList.add(createTask('Upload docs for Evaluation advice', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M7##') taskList.add(createTask('Release Evaluation Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M8') taskList.add(createTask('Follow up for payment to Evaluation Agency', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M9') taskList.add(createTask('Follow up for Evaluation report', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M9+') taskList.add(createTask('Follow up for Evaluation report', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M10') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M10+') taskList.add(createTask('Pay for exam', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M11') taskList.add(createTask('Follow up for NTS', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M11+') taskList.add(createTask('Exam Scheduling Advice to be released', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M11#') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M12') taskList.add(createTask('Follow up for exam prep and exam completion', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M13') taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M13+') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M13++') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M13#') taskList.add(createTask('Follow up to get exam result', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M14') taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M14+') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M14++') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M14#') taskList.add(createTask('Follow up to get exam result', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M15') taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M15+') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M15++') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M15#') taskList.add(createTask('Follow up to get exam result', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M16') taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M16+') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M16++') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M16#') taskList.add(createTask('Follow up to get exam result', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M17') taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M17+') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            if(enrolledObj.Stages__c == 'M17++') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            if(enrolledObj.Stages__c == 'M17#') taskList.add(createTask('Follow up to get exam result', enrolledObj.Id, 0, enrolledObj.OwnerId));
        }                      
    }
    
    
    static void createCMATasks(List<Course_Enrolled__c> cmaStatusChangedList, Map<Id, Course_Enrolled__c> oldMap) {
                      
    }
    
    
    static Task createTask(String subjectName, String recordId, Integer noOfDays, String ownerId) {
        Task newTask = new Task();
        newTask.Subject = subjectName;
        newTask.WhatId = recordId;
        newTask.Status = 'Not Started';
        newTask.Priority = 'High';
        newTask.Description = subjectName;
        newTask.ActivityDate = System.Date.today().addDays(noOfDays);
        newTask.OwnerId = ownerId;
        return newTask;
    }
}