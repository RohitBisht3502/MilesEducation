// @Depricated:
public class CourseEnrolledTriggerHandlerService {
/*
    public static void checkAndCreateNewTaskForInsert(List<Course_Enrolled__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        List<Course_Enrolled__c> cpaList = new List<Course_Enrolled__c>();
        List<Course_Enrolled__c> cmaList = new List<Course_Enrolled__c>();

        for (Course_Enrolled__c enrolledObj : newList) {
            if (enrolledObj == null) continue;
            if (String.isBlank(enrolledObj.Stages__c)) continue;
            if (enrolledObj.Course__c == 'CPA') cpaList.add(enrolledObj);
            if (enrolledObj.Course__c == 'CMA') cmaList.add(enrolledObj);
        }

        if (!cpaList.isEmpty()) createCPATasks(cpaList, null);
        if (!cmaList.isEmpty()) createCMATasks(cmaList, null);
    }

    public static void checkAndCreateNewTaskForStatusChange(Map<Id, Course_Enrolled__c> newMap, Map<Id, Course_Enrolled__c> oldMap) {
        List<Course_Enrolled__c> cpaStatusChangedList 	= new List<Course_Enrolled__c>();
        List<Course_Enrolled__c> cmaStatusChangedList 	= new List<Course_Enrolled__c>();
        
        for(Course_Enrolled__c enrolledObj : newMap.values()) {
            if(enrolledObj.Stages__c != oldMap.get(enrolledObj.Id).Stages__c) {
                if(enrolledObj.Course__c == 'CPA') cpaStatusChangedList.add(enrolledObj);
                if(enrolledObj.Course__c == 'CMA') cmaStatusChangedList.add(enrolledObj);   
            }
        }
        
        completePreviousStageTasks(cpaStatusChangedList);
        completePreviousStageTasks(cmaStatusChangedList);

        if(!cpaStatusChangedList.isEmpty()) createCPATasks(cpaStatusChangedList, oldMap);
        if(!cmaStatusChangedList.isEmpty()) createCMATasks(cmaStatusChangedList, oldMap);
    }

    static void completePreviousStageTasks(List<Course_Enrolled__c> statusChangedList) {
        if(statusChangedList == null || statusChangedList.isEmpty()) return;

        Set<Id> enrolledIds = new Set<Id>();
        for(Course_Enrolled__c enrolledObj : statusChangedList) {
            enrolledIds.add(enrolledObj.Id);
        }

        List<Task> taskToUpdate = new List<Task>();
        Set<Id> processedWhatIds = new Set<Id>();

        for(Task taskObj : [SELECT Id, WhatId, Status FROM Task WHERE WhatId IN :enrolledIds AND Status != 'Completed' ORDER BY WhatId, CreatedDate DESC]) {
            if(!processedWhatIds.contains(taskObj.WhatId)) {
                taskObj.Status = 'Completed';
                taskToUpdate.add(taskObj);
                processedWhatIds.add(taskObj.WhatId);
            }
        }

        if(!taskToUpdate.isEmpty()) {
            update taskToUpdate;
        }
    }
    
    
    static void createCPATasks(List<Course_Enrolled__c> cpaStatusChangedList, Map<Id, Course_Enrolled__c> oldMap) {
        List<Task> taskList = new List<Task>();
        String subjectName;
        for(Course_Enrolled__c enrolledObj : cpaStatusChangedList) {
            if(enrolledObj.Stages__c == 'M7+') taskList.add(createTask('Complete Onboarding', enrolledObj.Id, 0, enrolledObj.OwnerId));

            // this will done by File status part
            // if(enrolledObj.Stages__c == 'M7#') taskList.add(createTask('Upload docs for Evaluation advice', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M7#-') taskList.add(createTask('Upload docs for Evaluation advice', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M7##') taskList.add(createTask('Release Evaluation Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            // if(enrolledObj.Stages__c == 'M8') taskList.add(createTask('Follow up for payment to Evaluation Agency', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M9') taskList.add(createTask('Follow up for Evaluation report', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M9+') taskList.add(createTask('Follow up for Evaluation report', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M10') taskList.add(createTask('Release NTS Advice', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            // if(enrolledObj.Stages__c == 'M10+') taskList.add(createTask('Pay for exam', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M11') taskList.add(createTask('Follow up for NTS', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M11+') taskList.add(createTask('Exam Scheduling Advice to be released', enrolledObj.Id, 0, enrolledObj.GP_SPOC__c));
            // if(enrolledObj.Stages__c == 'M11#') taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, enrolledObj.OwnerId));
            // if(enrolledObj.Stages__c == 'M12') taskList.add(createTask('Follow up for exam prep and exam completion', enrolledObj.Id, 0, enrolledObj.OwnerId));
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

        if(!taskList.isEmpty()) {
            insert taskList;
        }              
    }
       
    static void createCMATasks(List<Course_Enrolled__c> cmaStatusChangedList, Map<Id, Course_Enrolled__c> oldMap) {
        List<Task> taskList = new List<Task>();

        for (Course_Enrolled__c enrolledObj : cmaStatusChangedList) {

            // Assign to SR SPOC (Owner)
            Id assigneeId = enrolledObj.OwnerId;

            if (enrolledObj.Stages__c == 'M7+')  taskList.add(createTask('Complete Onboarding', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M7#')  taskList.add(createTask('Assist on IMA Registration', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M7##') taskList.add(createTask('Assist on IMA Registration', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M8')   taskList.add(createTask('Assisit in IMA Memebership Seletion and Coupon Code redemption', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M9')   taskList.add(createTask('Schedule Exam and upload pro-metric', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M12')  taskList.add(createTask('Check for reschedule or Postpone of Exam ', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M13')  taskList.add(createTask('Exam experience and Result Check ', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M14')  taskList.add(createTask('Schedule/Reschedule for Failed  Exam and upload pro-metric', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M14#') taskList.add(createTask('Check for Exam prep and Appearance', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M15')  taskList.add(createTask('Schedule 2nd Exam  and Upload pro-metric', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M15#') taskList.add(createTask('Check for reschedule or Postpone of Exam ', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M18')  taskList.add(createTask('Share certification Advice', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M18+') taskList.add(createTask('Complete Certification Advice', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M18-') taskList.add(createTask('Reshare Certification Advice ', enrolledObj.Id, 0, assigneeId));
            if (enrolledObj.Stages__c == 'M18#') taskList.add(createTask('Support in Certification Application', enrolledObj.Id, 0, assigneeId));
        }

        if (!taskList.isEmpty()) {
            insert taskList;
        }
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
        */
}