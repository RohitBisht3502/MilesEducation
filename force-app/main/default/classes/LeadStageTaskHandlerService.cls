public class LeadStageTaskHandlerService {

    public static void checkAndCreateNewTaskForInsert(List<Lead__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        List<Lead__c> cpaList = new List<Lead__c>();
        List<Lead__c> cmaList = new List<Lead__c>();

        for (Lead__c leadObj : newList) {
            if (leadObj == null) continue;
            if (String.isBlank(leadObj.Stage__c)) continue;
            if (leadObj.Course__c == 'CPA') cpaList.add(leadObj);
            if (leadObj.Course__c == 'CMA') cmaList.add(leadObj);
        }

        if (!cpaList.isEmpty()) createCPATasks(cpaList, null);
        if (!cmaList.isEmpty()) createCMATasks(cmaList, null);
    }

    public static void checkAndCreateNewTaskForStatusChange(Map<Id, Lead__c> newMap, Map<Id, Lead__c> oldMap) {
        if (newMap == null || newMap.isEmpty() || oldMap == null) return;

        List<Lead__c> cpaStatusChangedList = new List<Lead__c>();
        List<Lead__c> cmaStatusChangedList = new List<Lead__c>();

        for (Lead__c leadObj : newMap.values()) {
            Lead__c oldRec = oldMap.get(leadObj.Id);
            if (oldRec == null) continue;
            if (leadObj.Stage__c == oldRec.Stage__c) continue;

            if (leadObj.Course__c == 'CPA') cpaStatusChangedList.add(leadObj);
            if (leadObj.Course__c == 'CMA') cmaStatusChangedList.add(leadObj);
        }

        completePreviousStageTasks(cpaStatusChangedList);
        completePreviousStageTasks(cmaStatusChangedList);

        if (!cpaStatusChangedList.isEmpty()) createCPATasks(cpaStatusChangedList, oldMap);
        if (!cmaStatusChangedList.isEmpty()) createCMATasks(cmaStatusChangedList, oldMap);
    }

    static void completePreviousStageTasks(List<Lead__c> statusChangedList) {
        if (statusChangedList == null || statusChangedList.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Lead__c leadObj : statusChangedList) {
            leadIds.add(leadObj.Id);
        }

        List<Task> taskToUpdate = new List<Task>();
        Set<Id> processedWhatIds = new Set<Id>();

        for (Task taskObj : [
            SELECT Id, WhatId, Status
            FROM Task
            WHERE WhatId IN :leadIds AND Status != 'Completed'
            ORDER BY WhatId, CreatedDate DESC
        ]) {
            if (!processedWhatIds.contains(taskObj.WhatId)) {
                taskObj.Status = 'Completed';
                taskToUpdate.add(taskObj);
                processedWhatIds.add(taskObj.WhatId);
            }
        }

        if (!taskToUpdate.isEmpty()) {
            update taskToUpdate;
        }
    }

    static void createCPATasks(List<Lead__c> cpaStatusChangedList, Map<Id, Lead__c> oldMap) {
        List<Task> taskList = new List<Task>();
        for (Lead__c leadObj : cpaStatusChangedList) {
            if (leadObj.Stage__c == 'M7+') taskList.add(createTask('Complete Onboarding', leadObj.Id, 0, leadObj.OwnerId));

            // this will done by File status part
            // if (leadObj.Stage__c == 'M7#')  taskList.add(createTask('Upload docs for Evaluation advice', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M7#-') taskList.add(createTask('Upload docs for Evaluation advice', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M7##') taskList.add(createTask('Release Evaluation Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            // if (leadObj.Stage__c == 'M8')   taskList.add(createTask('Follow up for payment to Evaluation Agency', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M9')   taskList.add(createTask('Follow up for Evaluation report', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M9+')  taskList.add(createTask('Follow up for Evaluation report', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M10')  taskList.add(createTask('Release NTS Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            // if (leadObj.Stage__c == 'M10+') taskList.add(createTask('Pay for exam', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M11')  taskList.add(createTask('Follow up for NTS', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M11+') taskList.add(createTask('Exam Scheduling Advice to be released', leadObj.Id, 0, getGpSpocId(leadObj)));
            // if (leadObj.Stage__c == 'M11#') taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, leadObj.OwnerId));
            // if (leadObj.Stage__c == 'M12')  taskList.add(createTask('Follow up for exam prep and exam completion', leadObj.Id, 0, leadObj.OwnerId));

            if (leadObj.Stage__c == 'M13')  taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M13+') taskList.add(createTask('Release NTS Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            if (leadObj.Stage__c == 'M13++') taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M13#') taskList.add(createTask('Follow up to get exam result', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M14')  taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M14+') taskList.add(createTask('Release NTS Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            if (leadObj.Stage__c == 'M14++') taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M14#') taskList.add(createTask('Follow up to get exam result', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M15')  taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M15+') taskList.add(createTask('Release NTS Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            if (leadObj.Stage__c == 'M15++') taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M15#') taskList.add(createTask('Follow up to get exam result', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M16')  taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M16+') taskList.add(createTask('Release NTS Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            if (leadObj.Stage__c == 'M16++') taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M16#') taskList.add(createTask('Follow up to get exam result', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M17')  taskList.add(createTask('Follow up for exam result and follow up to request NTS for any other exams', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M17+') taskList.add(createTask('Release NTS Advice', leadObj.Id, 0, getGpSpocId(leadObj)));
            if (leadObj.Stage__c == 'M17++') taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, leadObj.OwnerId));
            if (leadObj.Stage__c == 'M17#') taskList.add(createTask('Follow up to get exam result', leadObj.Id, 0, leadObj.OwnerId));
        }

        if (!taskList.isEmpty()) {
            insert taskList;
        }
    }

    static void createCMATasks(List<Lead__c> cmaStatusChangedList, Map<Id, Lead__c> oldMap) {
        List<Task> taskList = new List<Task>();

        for (Lead__c leadObj : cmaStatusChangedList) {
            Id assigneeId = leadObj.OwnerId;

            if (leadObj.Stage__c == 'M7+')  taskList.add(createTask('Complete Onboarding', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M7#')  taskList.add(createTask('Assist on IMA Registration', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M7##') taskList.add(createTask('Assist on IMA Registration', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M8')   taskList.add(createTask('Assisit in IMA Memebership Seletion and Coupon Code redemption', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M9')   taskList.add(createTask('Schedule Exam and upload pro-metric', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M12')  taskList.add(createTask('Check for reschedule or Postpone of Exam ', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M13')  taskList.add(createTask('Exam experience and Result Check ', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M14')  taskList.add(createTask('Schedule/Reschedule for Failed  Exam and upload pro-metric', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M14#') taskList.add(createTask('Check for Exam prep and Appearance', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M15')  taskList.add(createTask('Schedule 2nd Exam  and Upload pro-metric', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M15#') taskList.add(createTask('Check for reschedule or Postpone of Exam ', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M18')  taskList.add(createTask('Share certification Advice', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M18+') taskList.add(createTask('Complete Certification Advice', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M18-') taskList.add(createTask('Reshare Certification Advice ', leadObj.Id, 0, assigneeId));
            if (leadObj.Stage__c == 'M18#') taskList.add(createTask('Support in Certification Application', leadObj.Id, 0, assigneeId));
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

    private static Id getGpSpocId(Lead__c leadObj) {
        if (leadObj == null) return null;
        return (Id)leadObj.get('GP_SPOC__c');
    }
}