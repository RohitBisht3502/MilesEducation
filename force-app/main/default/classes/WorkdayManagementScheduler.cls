public with sharing class WorkdayManagementScheduler {
    public static final String DAILY_SEEDER_JOB_NAME = 'Workday Daily Attendance Seeder 12:05AM';
    public static final String LEGACY_MONTHLY_JOB_NAME = 'Workday Monthly Attendance Seeder';
    public static final String AUTO_CLOSE_JOB_NAME = 'Workday Daily Auto Close 11PM';

    @AuraEnabled
    public static void scheduleDefaultJobs() {
        Set<String> targetNames = new Set<String>{
            DAILY_SEEDER_JOB_NAME,
            LEGACY_MONTHLY_JOB_NAME,
            AUTO_CLOSE_JOB_NAME
        };
        for (CronTrigger triggerRow : [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :targetNames
        ]) {
            System.abortJob(triggerRow.Id);
        }

        // Daily at 12:05 AM
        System.schedule(
            DAILY_SEEDER_JOB_NAME,
            '0 5 0 * * ? *',
            new AttendanceMonthlySeederBatch()
        );

        // Daily at 11:05 PM
        System.schedule(
            AUTO_CLOSE_JOB_NAME,
            '0 5 23 * * ? *',
            new AttendanceAutoCloseBatch()
        );
    }
}