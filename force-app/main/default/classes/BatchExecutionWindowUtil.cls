public class BatchExecutionWindowUtil {

    public static Boolean canRun(String batchClassName) {

        List<Batch_Schedule_Config__mdt> configs =
            [SELECT Is_Active__c,
                    Start_Hour__c, End_Hour__c,
                    Run_On_Monday__c, Run_On_Tuesday__c, Run_On_Wednesday__c,
                    Run_On_Thursday__c, Run_On_Friday__c
             FROM Batch_Schedule_Config__mdt
             WHERE Batch_Class_Name__c = :batchClassName
             LIMIT 1];

        if (configs.isEmpty() || !configs[0].Is_Active__c) {
            return false;
        }
	
        Batch_Schedule_Config__mdt cfg = configs[0];

        Datetime nowDT = System.now();
        Integer currentHour = nowDT.hour();
        String today = nowDT.format('E'); // Mon, Tue...

        // ⏰ Time check
        if (currentHour < cfg.Start_Hour__c || currentHour >= cfg.End_Hour__c) {
            return false;
        }

        // 📅 Day check
        if (
            (today == 'Mon' && cfg.Run_On_Monday__c) ||
            (today == 'Tue' && cfg.Run_On_Tuesday__c) ||
            (today == 'Wed' && cfg.Run_On_Wednesday__c) ||
            (today == 'Thu' && cfg.Run_On_Thursday__c) ||
            (today == 'Fri' && cfg.Run_On_Friday__c)
        ) {
            return true;
        }

        return false;
    }
    
    // -------------------- NEW: OVERLAP CHECK --------------------
    public static Boolean isBatchAlreadyRunning(String batchClassName) {

        Integer runningJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = :batchClassName
            AND Status IN ('Processing', 'Preparing', 'Queued')
        ];

        return runningJobs > 0;
    }
}