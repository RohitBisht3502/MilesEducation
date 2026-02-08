public class TriggerRoundRobinPostEnrollment {

    public static void handleBeforeInsert(List<Course_Enrolled__c> newCourseEnrolleds) {
        if (newCourseEnrolleds == null || newCourseEnrolleds.isEmpty()) return;

        try {
            List<SObject> sobs = new List<SObject>();
            sobs.addAll(newCourseEnrolleds);

            RoundRobinAssigner.assignWithStickyAndRoundRobin(
                sobs,
                'Course_Enrolled__c',
                'SR - Post Enrollment'
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'RoundRobin failed in Course_Enrolled before insert: ' + e.getMessage());
            // If you want to block insert when assignment fails, uncomment:
            // for (Course_Enrolled__c ce : newCourseEnrolleds) ce.addError('Assignment failed: ' + e.getMessage());
        }
    }
}