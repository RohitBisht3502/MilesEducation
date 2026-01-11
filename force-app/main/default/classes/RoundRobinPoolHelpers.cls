public class RoundRobinPoolHelpers {

    public static void handleWeightChange(
        List<Round_Robin_Pool__c> newList,
        Map<Id, Round_Robin_Pool__c> oldMap
    ) {
        List<Activity_Log__c> logs = new List<Activity_Log__c>();

        for (Round_Robin_Pool__c pool : newList) {
            Round_Robin_Pool__c oldPool = oldMap.get(pool.Id);
            if (oldPool == null) continue;

            if (pool.Assigned_Weight__c != oldPool.Assigned_Weight__c) {

                logs.add(new Activity_Log__c(
                    Round_Robin_Pool__c = pool.Id,
                    Previous_weight__c = oldPool.Assigned_Weight__c,
                    New_Assinged_Weight__c = pool.Assigned_Weight__c,
                    Activity_Type__c = 'WEIGHT UPDATED',
                    Changed_Date_Time__c = System.now(),
                    Action_Performed_By__c = UserInfo.getUserId(),

                    // 🔥 REQUIRED FIELD FIX
                    Logging_Id__c =
                        pool.Id + '_' + String.valueOf(System.now().getTime()),

                    Description__c =
                        'Assigned Weight changed from ' +
                        String.valueOf(oldPool.Assigned_Weight__c) +
                        ' to ' +
                        String.valueOf(pool.Assigned_Weight__c)
                ));
            }
        }

        if (!logs.isEmpty()) {
            insert logs;
        }
    }
}