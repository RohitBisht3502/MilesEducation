public class GpFolderTaskHandler {

    private enum AssigneeType { SR_SPOC, GP_SPOC, CC_SPOC }

    private class Rule {
        String taskSubject;
        AssigneeType assigneeType;

        Rule(String taskSubject, AssigneeType assigneeType) {
            this.taskSubject = taskSubject;
            this.assigneeType = assigneeType;
        }
    }

    private static String norm(String value) {
        return String.valueOf(value).trim().toLowerCase();
    }

    private static String keyOf(String level, String step, String status) {
        return norm(level) + '||' + norm(step) + '||' + norm(status);
    }

    private static void addRule(
        Map<String, Rule> rules,
        String level,
        String step,
        String status,
        String subject,
        AssigneeType assigneeType
    ) {
        rules.put(keyOf(level, step, status), new Rule(subject, assigneeType));
    }

    private static final Map<String, Rule> RULES = initRules();

    private static Map<String, Rule> initRules() {
        Map<String, Rule> rules = new Map<String, Rule>();

        addRule(rules, 'M7#-', 'eligibility', 'Pending to upload', 'Upload docs for Evaluation advice', AssigneeType.SR_SPOC);
        addRule(rules, 'M7#-', 'eligibility', 'Re-upload', 'Upload docs for Evaluation advice', AssigneeType.SR_SPOC);
        addRule(rules, 'M7#-', 'eligibility', 'Under Review', 'Approve docs needed to release Evaluation advice', AssigneeType.GP_SPOC);
        addRule(rules, 'M7##', 'eligibility', 'Approved', 'Release Evaluation Advice', AssigneeType.GP_SPOC);

        addRule(rules, 'M8', 'evaluation', 'Yet to upload', 'Follow up for payment to Evaluation Agency', AssigneeType.SR_SPOC);
        addRule(rules, 'M8', 'evaluation', 'Pending to upload', 'Follow up for payment to Evaluation Agency', AssigneeType.SR_SPOC);
        addRule(rules, 'M8', 'evaluation', 'Re-upload', 'Re-upload proof of payment to Evaluation Agency', AssigneeType.SR_SPOC);
        addRule(rules, 'M8', 'evaluation', 'Under Review', 'Review NIES payment receipt', AssigneeType.SR_SPOC);

        addRule(rules, 'M9', 'evaluation', 'Yet to upload', 'Follow up for Evaluation report', AssigneeType.SR_SPOC);
        addRule(rules, 'M9+', 'evaluation', 'Re-upload', 'Follow up for Evaluation report', AssigneeType.SR_SPOC);
        addRule(rules, 'M9+', 'evaluation', 'Under Review', 'Approve the Evaluation report', AssigneeType.GP_SPOC);
        addRule(rules, 'M10', 'evaluation', 'Approved', 'Release NTS Advice', AssigneeType.GP_SPOC);

        addRule(rules, 'M11', 'nts', 'Yet to upload', 'Follow up for NTS', AssigneeType.SR_SPOC);
        addRule(rules, 'M11', 'nts', 'Re-upload', 'Follow up for NTS', AssigneeType.SR_SPOC);
        addRule(rules, 'M11', 'nts', 'Under Review', 'Approve NTS', AssigneeType.GP_SPOC);
        addRule(rules, 'M11+', 'nts', 'Approved', 'Exam Scheduling Advice to be released', AssigneeType.GP_SPOC);

        addRule(rules, 'M11#', 'exam', 'Yet to upload', 'Schedule Exam and upload pro-metric', AssigneeType.SR_SPOC);
        addRule(rules, 'M11#', 'exam', 'Re-upload', 'Schedule Exam and upload pro-metric', AssigneeType.SR_SPOC);
        addRule(rules, 'M11#', 'exam', 'Under Review', 'Verify Pro-metric', AssigneeType.GP_SPOC);

        addRule(rules, 'M12', 'last_minute', 'Approved', 'Follow up for exam prep and exam completion', AssigneeType.SR_SPOC);

        return rules;
    }

    public static void handleAfterInsert(List<GP_Folder__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        createTasks(newList, true, null);
    }

    public static void handleAfterUpdate(List<GP_Folder__c> newList, Map<Id, GP_Folder__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }
        createTasks(newList, false, oldMap);
    }

    private static void createTasks(List<GP_Folder__c> newList, Boolean isInsert, Map<Id, GP_Folder__c> oldMap) {
        Set<Id> leadIds = new Set<Id>();
        List<GP_Folder__c> toProcess = new List<GP_Folder__c>();

        for (GP_Folder__c folderRecord : newList) {
            if (folderRecord.Lead__c == null || String.isBlank(folderRecord.Status__c)) {
                continue;
            }

            if (isInsert) {
                toProcess.add(folderRecord);
                leadIds.add(folderRecord.Lead__c);
                continue;
            }

            GP_Folder__c oldRecord = oldMap.get(folderRecord.Id);
            if (oldRecord == null || folderRecord.Status__c == oldRecord.Status__c) {
                continue;
            }

            toProcess.add(folderRecord);
            leadIds.add(folderRecord.Lead__c);
        }

        if (toProcess.isEmpty()) {
            return;
        }

        completePreviousTasks(leadIds);

        Map<Id, Lead__c> leadMap = new Map<Id, Lead__c>([
            SELECT Id, OwnerId, GP_User__c
            FROM Lead__c
            WHERE Id IN :leadIds
        ]);

        Map<String, Task> existingOpenByLeadAndSubject = new Map<String, Task>();
        for (Task existingTask : [
            SELECT Id, WhatId, Subject, Status
            FROM Task
            WHERE WhatId IN :leadIds
            AND Status != 'Completed'
        ]) {
            existingOpenByLeadAndSubject.put(String.valueOf(existingTask.WhatId) + '||' + norm(existingTask.Subject), existingTask);
        }

        List<Task> tasksToInsert = new List<Task>();

        for (GP_Folder__c folderRecord : toProcess) {
            Lead__c leadRecord = leadMap.get(folderRecord.Lead__c);
            if (leadRecord == null) {
                continue;
            }

            Rule rule = RULES.get(keyOf(folderRecord.Level__c, folderRecord.Step__c, folderRecord.Status__c));
            if (rule == null) {
                continue;
            }

            Id ownerId;
            if (rule.assigneeType == AssigneeType.SR_SPOC) {
                ownerId = leadRecord.OwnerId;
            } else if (rule.assigneeType == AssigneeType.GP_SPOC) {
                ownerId = leadRecord.GP_User__c;
            } else {
                ownerId = leadRecord.OwnerId;
            }

            if (ownerId == null) {
                continue;
            }

            String duplicateKey = String.valueOf(leadRecord.Id) + '||' + norm(rule.taskSubject);
            if (existingOpenByLeadAndSubject.containsKey(duplicateKey)) {
                continue;
            }

            String source = isInsert ? 'insert' : 'update';
            Task taskRecord = new Task(
                Subject = rule.taskSubject,
                OwnerId = ownerId,
                WhatId = leadRecord.Id,
                ActivityDate = Date.today(),
                Status = 'Not Started',
                Priority = 'High',
                Description = 'Auto-created from GP Folder ' + source +
                    '. Level=' + folderRecord.Level__c +
                    ', Step=' + folderRecord.Step__c +
                    ', Status=' + folderRecord.Status__c +
                    ', GpFolderId=' + folderRecord.Id
            );

            tasksToInsert.add(taskRecord);
            existingOpenByLeadAndSubject.put(duplicateKey, taskRecord);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    private static void completePreviousTasks(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        List<Task> tasksToUpdate = new List<Task>();
        Set<Id> processedWhatIds = new Set<Id>();

        for (Task taskRecord : [
            SELECT Id, WhatId, Status
            FROM Task
            WHERE WhatId IN :leadIds
            AND Status != 'Completed'
            ORDER BY WhatId, CreatedDate DESC
        ]) {
            if (!processedWhatIds.contains(taskRecord.WhatId)) {
                taskRecord.Status = 'Completed';
                tasksToUpdate.add(taskRecord);
                processedWhatIds.add(taskRecord.WhatId);
            }
        }

        if (!tasksToUpdate.isEmpty()) {
            update tasksToUpdate;
        }
    }
}