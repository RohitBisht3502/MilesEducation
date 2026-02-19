public class LeadPostEnrollmentRoundRobinHandler {

    public static void handleBeforeUpdate(List<Lead__c> newList, Map<Id, Lead__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;

        List<Lead__c> toAssign = new List<Lead__c>();

        for (Lead__c n : newList) {
            Lead__c o = oldMap.get(n.Id);
            if (o == null) continue;

            if (n.Stage__c != 'M7+' || o.Stage__c == 'M7+') continue;

            // Store previous owner as CC SPOC
            if (o.OwnerId != null) {
                n.put('CC_Spoc__c', o.OwnerId);
            }

            toAssign.add(n);
        }

        if (toAssign.isEmpty()) return;

        List<SObject> sobs = new List<SObject>();
        sobs.addAll(toAssign);

        RoundRobinAssigner.assignWithStickyAndRoundRobin(
            sobs,
            'Lead__c',
            'SR - Post Enrollment'
        );
    }
}