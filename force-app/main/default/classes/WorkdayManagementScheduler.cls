public with sharing class WorkdayManagementScheduler {
    public static final String MONTHLY_JOB_NAME = 'Workday Monthly Attendance Seeder';
    public static final String AUTO_CLOSE_JOB_NAME = 'Workday Daily Auto Close 11PM';

    @AuraEnabled
    public static void scheduleDefaultJobs() {
        Set<String> targetNames = new Set<String>{ MONTHLY_JOB_NAME, AUTO_CLOSE_JOB_NAME };
        for (CronTrigger triggerRow : [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :targetNames
        ]) {
            System.abortJob(triggerRow.Id);
        }

        // 1st day of month, 12:15 AM
        System.schedule(
            MONTHLY_JOB_NAME,
            '0 15 0 1 * ? *',
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