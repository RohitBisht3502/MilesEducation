public without sharing class CourseEnrolledTriggerFrameworkHandler extends BaseTriggerHandler {

    public CourseEnrolledTriggerFrameworkHandler(
        List<Course_Enrolled__c> newList,
        List<Course_Enrolled__c> oldList,
        Map<Id, Course_Enrolled__c> newMap,
        Map<Id, Course_Enrolled__c> oldMap
    ) {
        super(
            (List<SObject>)newList,
            (List<SObject>)oldList,
            (Map<Id, SObject>)newMap,
            (Map<Id, SObject>)oldMap
        );
    }

    private List<Course_Enrolled__c> getNewCourses() {
        return (List<Course_Enrolled__c>)newList;
    }

    private Map<Id, Course_Enrolled__c> getOldCourseMap() {
        return (Map<Id, Course_Enrolled__c>)oldMap;
    }

    private List<Course_Enrolled__c> getOldCourses() {
        return (List<Course_Enrolled__c>)oldList;
    }

    public override void beforeInsert() {
        List<Course_Enrolled__c> recs = getNewCourses();
        if (recs == null || recs.isEmpty()) return;

        List<SObject> sobs = new List<SObject>();
        sobs.addAll(recs);

        RoundRobinAssigner.assignWithStickyAndRoundRobin(
            sobs,
            'Course_Enrolled__c',
            'SR - Post Enrollment'
        );        
    }

    public override void beforeUpdate() {

    }

    public override void afterInsert() {
        syncStudentOwner(getNewCourses(), null);
    }

    public override void afterUpdate() {
        syncStudentOwner(getNewCourses(), getOldCourseMap());
        //CourseEnrolledTriggerHandler.afterUpdate(getNewCourses(), getOldCourseMap());
    }

    public override void beforeDelete() {

    }

    public override void afterDelete() {

    }

    public override void afterUndelete() {

    }

    private static void syncStudentOwner(
        List<Course_Enrolled__c> newRecs,
        Map<Id, Course_Enrolled__c> oldMap
    ) {
        if (newRecs == null || newRecs.isEmpty()) return;

        Map<Id, Id> studentToOwner = new Map<Id, Id>();
        for (Course_Enrolled__c ce : newRecs) {
            if (ce.Student__c == null || ce.OwnerId == null) continue;
            if (oldMap != null) {
                Course_Enrolled__c oldRec = oldMap.get(ce.Id);
                if (oldRec != null && oldRec.OwnerId == ce.OwnerId) continue;
            }
            studentToOwner.put(ce.Student__c, ce.OwnerId);
        }

        if (studentToOwner.isEmpty()) return;

        List<Account> toUpdate = new List<Account>();
        for (Account acc : [
            SELECT Id, OwnerId
            FROM Account
            WHERE Id IN :studentToOwner.keySet()
        ]) {
            Id newOwnerId = studentToOwner.get(acc.Id);
            if (newOwnerId != null && acc.OwnerId != newOwnerId) {
                acc.OwnerId = newOwnerId;
                toUpdate.add(acc);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
