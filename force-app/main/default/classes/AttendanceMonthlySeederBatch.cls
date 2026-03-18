public with sharing class AttendanceMonthlySeederBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Name, Is_Active__c, Working_Days__c, Weekly_Off_Day__c
            FROM Employee__c
            WHERE Is_Active__c = true
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }

        List<Employee__c> employees = (List<Employee__c>) scope;
        Set<Id> employeeIds = new Set<Id>();
        for (Employee__c employee : employees) {
            employeeIds.add(employee.Id);
        }

        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Set<String> existingKeys = new Set<String>();
        for (Attendance__c existingAttendance : [
            SELECT Unique_Key__c
            FROM Attendance__c
            WHERE Employee__c IN :employeeIds
            AND Attendance_Date__c >= :monthStart
            AND Attendance_Date__c <= :monthEnd
        ]) {
            if (String.isNotBlank(existingAttendance.Unique_Key__c)) {
                existingKeys.add(existingAttendance.Unique_Key__c);
            }
        }

        List<Attendance__c> recordsToInsert = new List<Attendance__c>();
        for (Employee__c employee : employees) {
            Date cursorDate = monthStart;
            while (cursorDate <= monthEnd) {
                String keyValue = WorkdayManagementUtil.buildAttendanceKey(employee.Id, cursorDate);
                if (existingKeys.contains(keyValue)) {
                    cursorDate = cursorDate.addDays(1);
                    continue;
                }

                Boolean isWorking = WorkdayManagementUtil.isWorkingDay(employee, cursorDate);
                Attendance__c record = new Attendance__c();
                record.Employee__c = employee.Id;
                record.Attendance_Date__c = cursorDate;
                record.Unique_Key__c = keyValue;
                record.Day_Status__c = isWorking
                    ? WorkdayManagementUtil.DAY_STATUS_PLANNED
                    : WorkdayManagementUtil.DAY_STATUS_LEAVE;
                record.Is_Week_Off__c = !isWorking;
                record.Total_Break_Minutes__c = 0;
                record.Gross_Work_Minutes__c = 0;
                record.Net_Work_Minutes__c = 0;
                recordsToInsert.add(record);
                existingKeys.add(keyValue);
                cursorDate = cursorDate.addDays(1);
            }
        }

        if (!recordsToInsert.isEmpty()) {
            Database.insert(recordsToInsert, false);
        }
    }

    public void finish(Database.BatchableContext context) {
        // No-op.
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new AttendanceMonthlySeederBatch(), 200);
    }
}