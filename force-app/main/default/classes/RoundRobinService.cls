public without sharing class RoundRobinService {
    public static Boolean isExecuting = false;

    public static void assignForLeads(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) return;
        if (isExecuting) return;
        isExecuting = true;
        try {
            Map<String, List<Lead>> byKey = new Map<String, List<Lead>>();
            for (Lead l : leads) {
                String city   = RoundRobinHelper.normCity((String) l.get('City__c'));
                String source = RoundRobinHelper.normSource(l.Coming_From__c);
                String key    = RoundRobinHelper.keyOf('Lead', city, source);
                if (!byKey.containsKey(key)) byKey.put(key, new List<Lead>());
                byKey.get(key).add(l);
            }

            List<Round_Robin_Pool__c> poolUpdates = new List<Round_Robin_Pool__c>();
            List<RoundRobinRuntimeDAO.Runtime> runtimeToPersist = new List<RoundRobinRuntimeDAO.Runtime>();

            for (String key : byKey.keySet()) {
                RoundRobinHelper.BucketRef b = RoundRobinHelper.bucketFromKey(key);

                List<Round_Robin_Pool__c> pool = RoundRobinHelper.lockPoolMembers(b.objectApiName, b.cityUpper, b.sourceUpper);
                if (pool.isEmpty()) continue;

                RoundRobinRuntimeDAO.Runtime rt = RoundRobinRuntimeDAO.getOrCreateLocked(key);
                Id lastOwnerId = rt.lastAssignedUserId;

                for (Lead l : byKey.get(key)) {
                    RoundRobinHelper.PickResult pick = RoundRobinHelper.pickNext(pool, lastOwnerId);
                    if (pick.member == null) break;

                    l.OwnerId = pick.member.Sales_Rep__c;
                    lastOwnerId = l.OwnerId;
                    RoundRobinHelper.consumeSlot(pick.member);

                    rt.lastAssignedUserId = l.OwnerId;
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