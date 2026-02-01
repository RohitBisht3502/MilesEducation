public class StudentFileStatusTaskHandler {

    // Key format: LEVEL||FILETYPE||STATUS   (all trimmed + lowercase)
    private static String keyOf(String level, String fileType, String status) {
        String l = String.valueOf(level).trim().toLowerCase();
        String f = String.valueOf(fileType).trim().toLowerCase();
        String s = String.valueOf(status).trim().toLowerCase();
        return l + '||' + f + '||' + s;
    }

    // Who should own the task
    private enum AssigneeType { SR_SPOC, GP_SPOC, CC_SPOC }

    private class Rule {
        String taskSubject;
        AssigneeType assigneeType;
        Rule(String taskSubject, AssigneeType assigneeType) {
            this.taskSubject = taskSubject;
            this.assigneeType = assigneeType;
        }
    }

    // ====== RULES FROM YOUR IMAGE ======
    // NOTE: "Doc Name" column = your Student_File_Status__c.File_Type__c
    // NOTE: "Doc Status" column = your Student_File_Status__c.Status__c
    private static Map<String, Rule> buildRules() {
        Map<String, Rule> RULES = new Map<String, Rule>();

        // M7#- : Educational documents at eligibility
        RULES.put(
            keyOf('M7#-', 'Educational documents at eligibility', 'Pending to upload'),
            new Rule('Upload docs for Evaluation advice', AssigneeType.SR_SPOC)
        );
        RULES.put(
            keyOf('M7#-', 'Educational documents at eligibility', 'Re-upload'),
            new Rule('Upload docs for Evaluation advice', AssigneeType.SR_SPOC)
        );
        RULES.put(
            keyOf('M7#-', 'Educational documents at eligibility', 'Under Review'),
            new Rule('Approve docs needed to release Evaluation advice', AssigneeType.GP_SPOC)
        );

        // M7## : Educational documents at eligibility -> Approved
        RULES.put(
            keyOf('M7##', 'Educational documents at eligibility', 'Approved'),
            new Rule('Release Evaluation Advice', AssigneeType.GP_SPOC)
        );

        // M8 : payment follow-up
        RULES.put(
            keyOf('M8', 'FAQs Payment status', 'Not paid'),
            new Rule('Follow up for payment to Evaluation Agency', AssigneeType.SR_SPOC)
        );
        RULES.put(
            keyOf('M8', 'NIES Receipt', 'yet to upload'),
            new Rule('Follow up for payment to Evaluation Agency', AssigneeType.SR_SPOC)
        );

        return RULES;
    }

    public static void handleAfterUpdate(
        List<Student_File_Status__c> newList,
        Map<Id, Student_File_Status__c> oldMap
    ) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;

        Map<String, Rule> RULES = buildRules();

        // 1) Only process records where Status changed
        Set<Id> courseIds = new Set<Id>();
        List<Student_File_Status__c> changed = new List<Student_File_Status__c>();

        for (Student_File_Status__c sfs : newList) {
            Student_File_Status__c oldRec = oldMap.get(sfs.Id);
            if (oldRec == null) continue;

            if (sfs.Status__c != oldRec.Status__c) {
                changed.add(sfs);
                if (sfs.Course_Enrolled__c != null) courseIds.add(sfs.Course_Enrolled__c);
            }
        }
        if (changed.isEmpty() || courseIds.isEmpty()) return;

        // 2) Get Course Enrolled SPOCs
        Map<Id, Course_Enrolled__c> courseMap = new Map<Id, Course_Enrolled__c>([
            SELECT Id, OwnerId, GP_Spoc__c, CC_Spoc__c
            FROM Course_Enrolled__c
            WHERE Id IN :courseIds
        ]);

        // 3) (Optional but recommended) prevent duplicate open tasks:
        //    If same Subject already open for same Course Enrolled, skip creating.
        Set<Id> whatIds = new Set<Id>(courseIds);
        Map<String, Task> existingOpenByCourseAndSubject = new Map<String, Task>();
        for (Task t : [
            SELECT Id, WhatId, Subject, Status
            FROM Task
            WHERE WhatId IN :whatIds
              AND Status != 'Completed'
        ]) {
            String k = String.valueOf(t.WhatId) + '||' + String.valueOf(t.Subject).trim().toLowerCase();
            existingOpenByCourseAndSubject.put(k, t);
        }

        // 4) Create tasks
        List<Task> toInsert = new List<Task>();

        for (Student_File_Status__c sfs : changed) {
            Course_Enrolled__c ce = courseMap.get(sfs.Course_Enrolled__c);
            if (ce == null) continue;

            String ruleKey = keyOf(sfs.Level__c, sfs.File_Type__c, sfs.Status__c);
            Rule r = RULES.get(ruleKey);
            if (r == null) continue; // no rule, do nothing

            Id ownerId;
            if (r.assigneeType == AssigneeType.SR_SPOC) {
                ownerId = ce.OwnerId; // SR SPOC
            } else if (r.assigneeType == AssigneeType.GP_SPOC) {
                ownerId = ce.GP_Spoc__c;
            } else if (r.assigneeType == AssigneeType.CC_SPOC) {
                ownerId = ce.CC_Spoc__c;
            }

            if (ownerId == null) continue;

            // duplicate prevention key
            String dupKey = String.valueOf(ce.Id) + '||' + r.taskSubject.trim().toLowerCase();
            if (existingOpenByCourseAndSubject.containsKey(dupKey)) {
                continue;
            }

            Task t = new Task();
            t.Subject   = r.taskSubject;
            t.OwnerId   = ownerId;
            t.WhatId    = ce.Id;               // relate to Course Enrolled
            t.ActivityDate = Date.today();     // due today (change if you want)
            t.Status    = 'Not Started';
            t.Priority  = 'Normal';
            t.Description = 'Auto-created from Student File Status update. '
                          + 'Level=' + sfs.Level__c
                          + ', FileType=' + sfs.File_Type__c
                          + ', Status=' + sfs.Status__c
                          + ', StudentFileStatusId=' + sfs.Id;

            toInsert.add(t);

            // mark as existing so multiple SFS in same transaction won't create duplicates
            existingOpenByCourseAndSubject.put(dupKey, t);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}