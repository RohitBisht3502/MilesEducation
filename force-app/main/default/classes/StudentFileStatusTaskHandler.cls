public class StudentFileStatusTaskHandler {

    private enum AssigneeType { SR_SPOC, GP_SPOC, CC_SPOC }

    private class Rule {
        String taskSubject;
        AssigneeType assigneeType;
        Rule(String taskSubject, AssigneeType assigneeType) {
            this.taskSubject = taskSubject;
            this.assigneeType = assigneeType;
        }
    }

    private static String norm(String v) {
        return String.valueOf(v).trim().toLowerCase();
    }

    private static String keyOf(String level, String fileType, String status) {
        return norm(level) + '||' + norm(fileType) + '||' + norm(status);
    }

    private static void addRule(Map<String, Rule> m, String level, String fileType, String status, String subject, AssigneeType assignee) {
        m.put(keyOf(level, fileType, status), new Rule(subject, assignee));
    }

    private static final Map<String, Rule> RULES = initRules();
    private static Map<String, Rule> initRules() {
        Map<String, Rule> m = new Map<String, Rule>();

        addRule(m, 'M7#-', 'Educational documents at eligibility', 'Pending to upload', 'Upload docs for Evaluation advice', AssigneeType.SR_SPOC);
        addRule(m, 'M7#-', 'Educational documents at eligibility', 'Re-upload',        'Upload docs for Evaluation advice', AssigneeType.SR_SPOC);
        addRule(m, 'M7#-', 'Educational documents at eligibility', 'Under Review',    'Approve docs needed to release Evaluation advice', AssigneeType.GP_SPOC);
        addRule(m, 'M7##', 'Educational documents at eligibility', 'Approved',        'Release Evaluation Advice', AssigneeType.GP_SPOC);

        addRule(m, 'M8', 'FACs Payment status', 'Not paid',     'Follow up for payment to Evaluation Agency', AssigneeType.SR_SPOC);
        addRule(m, 'M8', 'NIES Receipt',        'Yet to upload','Follow up for payment to Evaluation Agency', AssigneeType.SR_SPOC);
        addRule(m, 'M8', 'NIES Receipt',        'Re-upload',    'Re-upload proof of payment to Evaluation Agency', AssigneeType.SR_SPOC);
        addRule(m, 'M8', 'NIES Receipt',        'Under Review', 'Review NIES payment receipt', AssigneeType.SR_SPOC);

        addRule(m, 'M9',  'Evaluation report', 'Yet to upload', 'Follow up for Evaluation report', AssigneeType.SR_SPOC);
        addRule(m, 'M9+', 'Evaluation report', 'Re-upload',     'Follow up for Evaluation report', AssigneeType.SR_SPOC);
        addRule(m, 'M9+', 'Evaluation report', 'Under Review',  'Approve the Evaluation report',   AssigneeType.GP_SPOC);
        addRule(m, 'M10', 'Evaluation report', 'Approved',      'Release NTS Advice',              AssigneeType.GP_SPOC);

        addRule(m, 'M11',  'NTS document', 'Yet to upload', 'Follow up for NTS', AssigneeType.SR_SPOC);
        addRule(m, 'M11',  'NTS document', 'Re-upload',     'Follow up for NTS', AssigneeType.SR_SPOC);
        addRule(m, 'M11',  'NTS document', 'Under Review',  'Approve NTS',       AssigneeType.GP_SPOC);
        addRule(m, 'M11+', 'NTS document', 'Approved',      'Exam Scheduling Advice to be released', AssigneeType.GP_SPOC);

        addRule(m, 'M11#', 'Pro-metric', 'Yet to upload', 'Schedule Exam and upload pro-metric', AssigneeType.SR_SPOC);
        addRule(m, 'M11#', 'Pro-metric', 'Re-upload',     'Schedule Exam and upload pro-metric', AssigneeType.SR_SPOC);
        addRule(m, 'M11#', 'Pro-metric', 'Under Review',  'Verify Pro-metric',                   AssigneeType.GP_SPOC);

        addRule(m, 'M12', 'Pro-metric', 'Approved', 'Follow up for exam prep and exam completion', AssigneeType.SR_SPOC);

        return m;
    }

    public static void handleAfterInsert(List<Student_File_Status__c> newList) {
        if (newList == null || newList.isEmpty()) return;
        createTasks(newList, true, null);
    }

    public static void handleAfterUpdate(List<Student_File_Status__c> newList, Map<Id, Student_File_Status__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;
        createTasks(newList, false, oldMap);
    }

    private static void createTasks(List<Student_File_Status__c> newList,Boolean isInsert, Map<Id, Student_File_Status__c> oldMap) {
        Set<Id> courseIds = new Set<Id>();
        List<Student_File_Status__c> toProcess = new List<Student_File_Status__c>();

        for (Student_File_Status__c sfs : newList) {
            if (sfs.Course_Enrolled__c == null) continue;
            if (String.isBlank(sfs.Status__c)) continue;

            if (isInsert) {
                toProcess.add(sfs);
                courseIds.add(sfs.Course_Enrolled__c);
                continue;
            }

            Student_File_Status__c oldRec = oldMap.get(sfs.Id);
            if (oldRec == null) continue;
            if (sfs.Status__c == oldRec.Status__c) continue;

            toProcess.add(sfs);
            courseIds.add(sfs.Course_Enrolled__c);
        }

        if (toProcess.isEmpty()) return;

        completePreviousTasks(courseIds);

        Map<Id, Course_Enrolled__c> courseMap = new Map<Id, Course_Enrolled__c>([
            SELECT Id, OwnerId, GP_Spoc__c, CC_Spoc__c FROM Course_Enrolled__c WHERE Id IN :courseIds
        ]);

        Map<String, Task> existingOpenByCourseAndSubject = new Map<String, Task>();
        for (Task t : [SELECT Id, WhatId, Subject, Status FROM Task WHERE WhatId IN :courseIds AND Status != 'Completed']) {
            existingOpenByCourseAndSubject.put(String.valueOf(t.WhatId) + '||' + norm(t.Subject), t);
        }

        List<Task> toInsert = new List<Task>();

        for (Student_File_Status__c sfs : toProcess) {
            Course_Enrolled__c ce = courseMap.get(sfs.Course_Enrolled__c);
            if (ce == null) continue;

            Rule r = RULES.get(keyOf(sfs.Level__c, sfs.File_Type__c, sfs.Status__c));
            if (r == null) continue;

            Id ownerId;
            if (r.assigneeType == AssigneeType.SR_SPOC) ownerId = ce.OwnerId;
            else if (r.assigneeType == AssigneeType.GP_SPOC) ownerId = ce.GP_Spoc__c;
            else ownerId = ce.CC_Spoc__c;

            if (ownerId == null) continue;

            String dupKey = String.valueOf(ce.Id) + '||' + norm(r.taskSubject);
            if (existingOpenByCourseAndSubject.containsKey(dupKey)) continue;

            String source = isInsert ? 'insert' : 'update';
            Task t = new Task(
                Subject      = r.taskSubject,
                OwnerId      = ownerId,
                WhatId       = ce.Id,
                ActivityDate = Date.today(),
                Status       = 'Not Started',
                Priority     = 'High',
                Description  = 'Auto-created from Student File Status ' + source + '. Level=' + sfs.Level__c +
                               ', FileType=' + sfs.File_Type__c + ', Status=' + sfs.Status__c +
                               ', StudentFileStatusId=' + sfs.Id
            );

            toInsert.add(t);
            existingOpenByCourseAndSubject.put(dupKey, t);
        }

        if (!toInsert.isEmpty()) insert toInsert;
    }

    private static void completePreviousTasks(Set<Id> courseIds) {
        if (courseIds == null || courseIds.isEmpty()) return;

        List<Task> taskToUpdate = new List<Task>();
        Set<Id> processedWhatIds = new Set<Id>();

        for (Task taskObj : [
            SELECT Id, WhatId, Status FROM Task WHERE WhatId IN :courseIds AND Status != 'Completed' ORDER BY WhatId, CreatedDate DESC]) {
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
}