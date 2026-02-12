/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RoundRobinService {
    public static Boolean isExecuting = false;

    public static void assignForRecords(List<SObject> records, RoundRobinConfigProvider.Config cfg) {
        if (records == null || records.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'RoundRobinService.assignForRecords: no records to assign');
            return;
        }
        if (isExecuting) {
            System.debug(LoggingLevel.WARN, 'RoundRobinService.assignForRecords: already executing, skipping');
            return;
        }
        isExecuting = true;

        try {
            System.debug(LoggingLevel.INFO, 'RoundRobinService.assignForRecords: start, records=' + records.size() + ', object=' + cfg.objectApiName);
            System.debug(LoggingLevel.INFO, 'CONFIG >>' + cfg);
            Map<String, List<SObject>> byKey = new Map<String, List<SObject>>();

            for (SObject s : records) {
                String city   = RoundRobinHelper.normCity(cfg.cityField != null ? String.valueOf(s.get(cfg.cityField)) : null);
                String source = cfg.ignoreSource ? '(ANY)' : RoundRobinHelper.normSource(cfg.sourceField != null ? String.valueOf(s.get(cfg.sourceField)) : null);
                String course = cfg.ignoreCourseBucket ? '(ANY)' : RoundRobinHelper.normCourse(cfg.courseField != null ? String.valueOf(s.get(cfg.courseField)) : null);
                System.debug('course >> '+course);
                String key = RoundRobinHelper.keyOf(cfg.objectApiName, city, source, course, cfg.typeValue);

                if (!byKey.containsKey(key)) byKey.put(key, new List<SObject>());
                byKey.get(key).add(s);
            }

            List<Round_Robin_Pool__c> poolUpdates = new List<Round_Robin_Pool__c>();
            List<RoundRobinRuntimeDAO.Runtime> runtimeToPersist = new List<RoundRobinRuntimeDAO.Runtime>();
            Integer totalAssigned = 0;

            for (String key : byKey.keySet()) {
                RoundRobinHelper.BucketRef b = RoundRobinHelper.bucketFromKey(key);
                System.debug('b >>> '+b);

                List<Round_Robin_Pool__c> pool =
                    RoundRobinHelper.lockPoolMembers(b.objectApiName, b.cityUpper, b.sourceUpper, b.courseUpper, b.typeValue, cfg.ignoreSource, cfg.ignoreCourseBucket);

                    System.debug('RoundRobinHelper.lockPoolMembers >>> '+pool);

                if (pool.isEmpty()) {
                    System.debug(LoggingLevel.INFO, 'RoundRobinService.assignForRecords: empty pool for key=' + key);
                    continue;
                }

                RoundRobinRuntimeDAO.Runtime rt = RoundRobinRuntimeDAO.getOrCreateLocked(key);
                Id lastAssignedUserId = rt.lastAssignedUserId;
                Integer assignedForKey = 0;

                for (SObject s : byKey.get(key)) {
                    RoundRobinHelper.PickResult pick = RoundRobinHelper.pickNext(pool, lastAssignedUserId);
                    if (pick.member == null) {
                        System.debug(LoggingLevel.INFO, 'RoundRobinService.assignForRecords: no eligible member for key=' + key);
                        break;
                    }

                    Id assignedUserId = pick.member.Sales_Rep__c;

                    if (cfg.assignToField == 'OwnerId') {
                        s.put('OwnerId', assignedUserId);
                    } else {
                        s.put(cfg.assignToField, assignedUserId);
                    }

                    lastAssignedUserId = assignedUserId;
                    assignedForKey++;

                    RoundRobinHelper.consumeSlot(pick.member);

                    rt.lastAssignedUserId = lastAssignedUserId;
                    rt.lastAssignedAt = System.now();
                    if (pick.cycleReset == true) rt.cycleStartedAt = System.now();
                }

                totalAssigned += assignedForKey;
                poolUpdates.addAll(pool);
                runtimeToPersist.add(rt);
            }

            if (!poolUpdates.isEmpty()) update poolUpdates;
            for (RoundRobinRuntimeDAO.Runtime rt : runtimeToPersist) {
                RoundRobinRuntimeDAO.upsertLocked(rt);
            }
            System.debug(LoggingLevel.INFO, 'RoundRobinService.assignForRecords: done, assigned=' + totalAssigned + ', poolsUpdated=' + poolUpdates.size() + ', runtimes=' + runtimeToPersist.size());

        } finally {
            isExecuting = false;
        }
    }
}