public class CourseEnrolledTriggerHandle {

    public static void handleAfter(
        List<Course_Enrolled__c> newList,
        Map<Id, Course_Enrolled__c> oldMap
    ) {

        List<Course_Enrolled__c> m7PlusCPARecords = new List<Course_Enrolled__c>();

        for (Course_Enrolled__c ce : newList) {

            Course_Enrolled__c oldCe =
                oldMap != null ? oldMap.get(ce.Id) : null;

            Boolean movedToM7Plus =
                ce.Stages__c == 'M7+' &&
                (oldCe == null || oldCe.Stages__c != 'M7+');

            if (
                ce.Course__c == 'CPA' &&
                movedToM7Plus
            ) {
                m7PlusCPARecords.add(ce);
            }
        }

        if (!m7PlusCPARecords.isEmpty()) {
            CPAScenarioHelper.handleM7Plus(m7PlusCPARecords);
        }
    }
}