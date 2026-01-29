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
            'Round Robin'
        );        
    }

    public override void beforeUpdate() {

    }

    public override void afterInsert() {

    }

    public override void afterUpdate() {
        //CourseEnrolledTriggerHandler.afterUpdate(getNewCourses(), getOldCourseMap());
    }

    public override void beforeDelete() {

    }

    public override void afterDelete() {

    }

    public override void afterUndelete() {

    }
}