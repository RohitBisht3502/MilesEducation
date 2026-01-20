public class CPAScenarioHelper {

        public static void handleM7Plus(List<Course_Enrolled__c> records) {

        Set<Id> courseEnrolledIds = new Set<Id>();
        for (Course_Enrolled__c ce : records) {
            courseEnrolledIds.add(ce.Id);
        }

        // Fetch existing onboarding tasks
        Map<Id, Task> existingTasksMap = new Map<Id, Task>();
        for (Task t : [
            SELECT Id, WhatId
            FROM Task
            WHERE WhatId IN :courseEnrolledIds
            AND Subject = 'Complete Onboarding'
        ]) {
            existingTasksMap.put(t.WhatId, t);
        }

        List<Task> tasksToInsert = new List<Task>();

        for (Course_Enrolled__c ce : records) {

            //  Skip if task already exists
            if (existingTasksMap.containsKey(ce.Id)) {
                continue;
            }

            if (ce.CC_Spoc__c == null) {
                continue;
            }

            Task t = new Task();
            t.Subject = 'Complete Onboarding';
            t.WhatId = ce.Id;
            t.OwnerId = ce.CC_Spoc__c;
            t.Status = 'Not Started';
            t.Priority = 'High';
            t.ActivityDate = Date.today().addDays(1);

            t.Description =
                'CPA – M7+ Scenario\n' +
                'SLA: 7 days to move to M7#\n' +
                'Max Follow-up: 3 days\n' +
                'Escalation: SR Manager';

            tasksToInsert.add(t);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }


  public static void handleM7Minus(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) {
        ceIds.add(ce.Id);
    }


    Set<Id> alreadyHasTask = new Set<Id>();
    for (Task t : [
        SELECT Id, WhatId
        FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'M7#- | Incomplete Documents'
    ]) {
        alreadyHasTask.add(t.WhatId);
    }

    List<Task> tasksToInsert = new List<Task>();

    for (Course_Enrolled__c ce : records) {

       
        if (alreadyHasTask.contains(ce.Id)) {
            continue;
        }

    
        if (ce.CC_Spoc__c == null) {
            continue;
        }

        Task t = new Task();
        t.WhatId = ce.Id;
        t.Subject = 'M7#- | Incomplete Documents';
        t.OwnerId = ce.CC_Spoc__c;
        t.Status = 'Not Started';
        t.Priority = 'Normal';

        tasksToInsert.add(t);
    }

    if (!tasksToInsert.isEmpty()) {
        insert tasksToInsert;
    }
}
    
    public static void handleM7DoubleHash(List<Course_Enrolled__c> records) {

   
    User gpSpocUser;

    List<User> gpUsers = [
        SELECT Id
        FROM User
        WHERE IsActive = true
        AND UserRole.Name = 'GP SPOC'
        LIMIT 1
    ];

    if (!gpUsers.isEmpty()) {
        gpSpocUser = gpUsers[0];
    }

    if (gpSpocUser == null) {
        return; 
    }

  
        Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) {
        ceIds.add(ce.Id);
    }

    Set<Id> alreadyHasTask = new Set<Id>();
    for (Task t : [
        SELECT Id, WhatId
        FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Release Evaluation Advice'
    ]) {
        alreadyHasTask.add(t.WhatId);
    }

    //Create Tasks
    List<Task> tasksToInsert = new List<Task>();

    for (Course_Enrolled__c ce : records) {

        if (alreadyHasTask.contains(ce.Id)) continue;

        Task t = new Task();
        t.Subject      = 'Release Evaluation Advice';
        t.WhatId       = ce.Id;
        t.OwnerId      = gpSpocUser.Id; 
        t.Status       = 'Not Started';
        t.Priority     = 'Normal';
        t.ActivityDate = Date.today().addDays(1);

        tasksToInsert.add(t);
    }

    if (!tasksToInsert.isEmpty()) {
        insert tasksToInsert;
    }
}




  public static void handleM8(List<Course_Enrolled__c> records) {

    if (records.isEmpty()) return;

   
    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) {
        ceIds.add(ce.Id);
    }

 
    Set<Id> alreadyHasTask = new Set<Id>();
    for (Task t : [
        SELECT Id, WhatId
        FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Follow up for payment to Evaluation Agency'
    ]) {
        alreadyHasTask.add(t.WhatId);
    }

   
    List<Task> tasksToInsert = new List<Task>();

    for (Course_Enrolled__c ce : records) {

        if (alreadyHasTask.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject      = 'Follow up for payment to Evaluation Agency';
        t.WhatId       = ce.Id;
        t.OwnerId      = ce.CC_Spoc__c;  
        t.Status       = 'Not Started';
        t.Priority     = 'Normal';
        t.ActivityDate = Date.today().addDays(1); 

        tasksToInsert.add(t);
    }

   
    if (!tasksToInsert.isEmpty()) {
        insert tasksToInsert;
    }
}
    public static void handleM9(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) {
        ceIds.add(ce.Id);
    }

    Set<Id> alreadyHasTask = new Set<Id>();
    for (Task t : [
        SELECT WhatId
        FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Follow up for Evaluation report'
    ]) {
        alreadyHasTask.add(t.WhatId);
    }

    List<Task> tasksToInsert = new List<Task>();

    for (Course_Enrolled__c ce : records) {

        if (alreadyHasTask.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject      = 'Follow up for Evaluation report';
        t.WhatId       = ce.Id;
        t.OwnerId      = ce.CC_Spoc__c; // SR SPOC
        t.Status       = 'Not Started';
        t.Priority     = 'Normal';
        t.ActivityDate = Date.today().addDays(1);

        tasksToInsert.add(t);
    }

    if (!tasksToInsert.isEmpty()) {
        insert tasksToInsert;
    }
}

    public static void handleM9Plus(List<Course_Enrolled__c> records) {

    User gpSpoc = [
        SELECT Id FROM User
        WHERE IsActive = true
        AND UserRole.Name = 'GP SPOC'
        LIMIT 1
    ];

    if (gpSpoc == null) return;

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Approve Evaluation report'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;

        Task t = new Task();
        t.Subject      = 'Approve Evaluation report';
        t.WhatId       = ce.Id;
        t.OwnerId      = gpSpoc.Id;
        t.Status       = 'Not Started';
        t.Priority     = 'High';
        t.ActivityDate = Date.today();

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    public static void handleM10(List<Course_Enrolled__c> records) {

    User gpSpoc = [
        SELECT Id FROM User
        WHERE IsActive = true
        AND UserRole.Name = 'GP SPOC'
        LIMIT 1
    ];

    if (gpSpoc == null) return;

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Release NTS Advice'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;

        Task t = new Task();
        t.Subject      = 'Release NTS Advice';
        t.WhatId       = ce.Id;
        t.OwnerId      = gpSpoc.Id;
        t.Status       = 'Not Started';
        t.Priority     = 'High';
        t.ActivityDate = Date.today();

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    
    public static void handleM10Plus(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Pay for exam'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject      = 'Pay for exam';
        t.WhatId       = ce.Id;
        t.OwnerId      = ce.CC_Spoc__c;
        t.Status       = 'Not Started';
        t.Priority     = 'Normal';
        t.ActivityDate = Date.today().addDays(1);

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    public static void handleM11(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Follow up for NTS'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject  = 'Follow up for NTS';
        t.WhatId   = ce.Id;
        t.OwnerId = ce.CC_Spoc__c;
        t.Status  = 'Not Started';
        t.Priority = 'Normal';

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    
    public static void handleM11Plus(List<Course_Enrolled__c> records) {

    User gpSpoc = [
        SELECT Id FROM User
        WHERE IsActive = true
        AND UserRole.Name = 'GP SPOC'
        LIMIT 1
    ];

    if (gpSpoc == null) return;

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Approve NTS'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;

        Task t = new Task();
        t.Subject  = 'Approve NTS';
        t.WhatId   = ce.Id;
        t.OwnerId = gpSpoc.Id;
        t.Status  = 'Not Started';
        t.Priority = 'High';

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    
    public static void handleM11Hash(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Schedule Exam and upload pro-metric'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject  = 'Schedule Exam and upload pro-metric';
        t.WhatId   = ce.Id;
        t.OwnerId = ce.CC_Spoc__c;
        t.Status  = 'Not Started';
        t.Priority = 'Normal';

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    
    public static void handleM12(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Follow up for exam prep and exam completion'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject  = 'Follow up for exam prep and exam completion';
        t.WhatId   = ce.Id;
        t.OwnerId = ce.CC_Spoc__c;
        t.Status  = 'Not Started';

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    
    public static void handleExamFollowUp(List<Course_Enrolled__c> records) {

    Set<Id> ceIds = new Set<Id>();
    for (Course_Enrolled__c ce : records) ceIds.add(ce.Id);

    Set<Id> existing = new Set<Id>();
    for (Task t : [
        SELECT WhatId FROM Task
        WHERE WhatId IN :ceIds
        AND Subject = 'Follow up for exam result'
    ]) {
        existing.add(t.WhatId);
    }

    List<Task> tasks = new List<Task>();

    for (Course_Enrolled__c ce : records) {
        if (existing.contains(ce.Id)) continue;
        if (ce.CC_Spoc__c == null) continue;

        Task t = new Task();
        t.Subject  = 'Follow up for exam result';
        t.WhatId   = ce.Id;
        t.OwnerId = ce.CC_Spoc__c;
        t.Status  = 'Not Started';

        tasks.add(t);
    }

    if (!tasks.isEmpty()) insert tasks;
}

    

}