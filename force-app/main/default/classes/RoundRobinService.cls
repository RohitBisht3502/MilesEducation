/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RoundRobinService {
    public static Boolean isExecuting = false;

    public static void assignForLeads(List<Lead__c> leads ,String type) {
        if (leads == null || leads.isEmpty()) return;
        if (isExecuting) return;
        isExecuting = true;

        String normType = String.isBlank(type) ? 'Round Robin' : type.trim();
        Boolean isEligibility = normType != null && normType.equalsIgnoreCase('Eligibility Criteria');

        try {
            Map<String, List<Lead__c>> byKey = new Map<String, List<Lead__c>>();
            for (Lead__c l : leads) {
                String city   = RoundRobinHelper.normCity((String) l.get('City__c'));
                String source = isEligibility ? '(ANY)' : RoundRobinHelper.normSource(l.Source__c);
                String course = RoundRobinHelper.normCourse((String) l.get('Course__c'));
                String key    = RoundRobinHelper.keyOf('Lead', city, source,course,normType);
                if (!byKey.containsKey(key)) byKey.put(key, new List<Lead__c>());
                byKey.get(key).add(l);
            }

            List<Round_Robin_Pool__c> poolUpdates = new List<Round_Robin_Pool__c>();
            List<RoundRobinRuntimeDAO.Runtime> runtimeToPersist = new List<RoundRobinRuntimeDAO.Runtime>();

            for (String key : byKey.keySet()) {
                RoundRobinHelper.BucketRef b = RoundRobinHelper.bucketFromKey(key);

                List<Round_Robin_Pool__c> pool = RoundRobinHelper.lockPoolMembers(b.objectApiName, b.cityUpper, b.sourceUpper,b.courseUpper,b.typeValue );
                if (pool.isEmpty()) continue;

                RoundRobinRuntimeDAO.Runtime rt = RoundRobinRuntimeDAO.getOrCreateLocked(key);
                Id lastAssignedUserId = rt.lastAssignedUserId;

                for (Lead__c l : byKey.get(key)) {
                    RoundRobinHelper.PickResult pick = RoundRobinHelper.pickNext(pool, lastAssignedUserId);
                    if (pick.member == null) break;
                    Id assignedUserId = pick.member.Sales_Rep__c;

                    if (isEligibility) {
                        l.GP_User__c = assignedUserId;
                    }else{
                       l.OwnerId = assignedUserId;
                    }

                    lastAssignedUserId = assignedUserId;

                    RoundRobinHelper.consumeSlot(pick.member);

                    rt.lastAssignedUserId = lastAssignedUserId; 
                    rt.lastAssignedAt = System.now();
                    if (pick.cycleReset == true) rt.cycleStartedAt = System.now();
                }

                poolUpdates.addAll(pool);
                runtimeToPersist.add(rt);
            }

            if (!poolUpdates.isEmpty()) update poolUpdates;
            for (RoundRobinRuntimeDAO.Runtime rt : runtimeToPersist) {
                RoundRobinRuntimeDAO.upsertLocked(rt);
            }
        } finally {
            isExecuting = false;
        }
    }
}