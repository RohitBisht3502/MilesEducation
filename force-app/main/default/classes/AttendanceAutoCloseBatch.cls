public with sharing class AttendanceAutoCloseBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext context) {
        Date todayDate = Date.today();
        return Database.getQueryLocator([
            SELECT Id, Employee__c, Attendance_Date__c, Start_Time__c, End_Time__c, Day_Status__c,
                   Auto_Ended__c, Total_Break_Minutes__c, Gross_Work_Minutes__c, Net_Work_Minutes__c,
                   Day_Summary__c, Is_Non_Business_Hours__c, Is_Week_Off__c
            FROM Attendance__c
            WHERE Start_Time__c != null
            AND End_Time__c = null
            AND Attendance_Date__c <= :todayDate
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }

        List<Attendance__c> attendanceScope = (List<Attendance__c>) scope;
        Map<Id, Attendance__c> attendanceById = new Map<Id, Attendance__c>();
        Map<Id, DateTime> forcedEndByAttendance = new Map<Id, DateTime>();
        List<Attendance__c> attendanceToUpdate = new List<Attendance__c>();
        Map<Id, Employee__c> employeeSnapshots = new Map<Id, Employee__c>();

        for (Attendance__c attendance : attendanceScope) {
            Date dateValue = attendance.Attendance_Date__c == null ? Date.today() : attendance.Attendance_Date__c;
            DateTime forcedEnd = DateTime.newInstance(dateValue, Time.newInstance(23, 0, 0, 0));

            // Skip current-day records if batch runs before 11 PM.
            if (dateValue == Date.today() && forcedEnd > System.now()) {
                continue;
            }

            attendance.End_Time__c = forcedEnd;
            attendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_AUTO_ENDED;
            attendance.Auto_Ended__c = true;
            attendanceToUpdate.add(attendance);
            attendanceById.put(attendance.Id, attendance);
            forcedEndByAttendance.put(attendance.Id, forcedEnd);

            if (dateValue == Date.today() && attendance.Employee__c != null) {
                Employee__c employeeUpdate = new Employee__c();
                employeeUpdate.Id = attendance.Employee__c;
                employeeUpdate.Current_Day_Status__c = 'Ended';
                employeeUpdate.Current_Day_End__c = forcedEnd;
                employeeSnapshots.put(employeeUpdate.Id, employeeUpdate);
            }
        }

        if (attendanceToUpdate.isEmpty()) {
            return;
        }

        Set<Id> attendanceIds = attendanceById.keySet();
        List<Break_Time__c> openBreaks = [
            SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c, Break_Status__c,
                   Sequence_Number__c, Auto_Ended__c
            FROM Break_Time__c
            WHERE Attendance__c IN :attendanceIds
            AND Break_End__c = null
        ];

        for (Break_Time__c breakItem : openBreaks) {
            DateTime forcedEnd = forcedEndByAttendance.get(breakItem.Attendance__c);
            if (forcedEnd == null) {
                continue;
            }
            breakItem.Break_End__c = forcedEnd;
            breakItem.Duration_Minutes__c = WorkdayManagementUtil.minutesBetween(breakItem.Break_Start__c, forcedEnd);
            breakItem.Break_Status__c = WorkdayManagementUtil.BREAK_STATUS_AUTO_ENDED;
            breakItem.Auto_Ended__c = true;
        }

        if (!openBreaks.isEmpty()) {
            update openBreaks;
        }

        Map<Id, List<Break_Time__c>> breaksByAttendance = new Map<Id, List<Break_Time__c>>();
        for (Id attendanceId : attendanceIds) {
            breaksByAttendance.put(attendanceId, new List<Break_Time__c>());
        }

        for (Break_Time__c breakItem : [
            SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c, Break_Status__c,
                   Sequence_Number__c
            FROM Break_Time__c
            WHERE Attendance__c IN :attendanceIds
            ORDER BY Sequence_Number__c ASC, Break_Start__c ASC
        ]) {
            breaksByAttendance.get(breakItem.Attendance__c).add(breakItem);
        }

        for (Attendance__c attendance : attendanceToUpdate) {
            List<Break_Time__c> breaks = breaksByAttendance.get(attendance.Id);
            WorkdayManagementUtil.recalculateAttendance(attendance, breaks, attendance.End_Time__c);
            attendance.Day_Summary__c = WorkdayManagementUtil.buildDaySummary(attendance, breaks);
        }

        update attendanceToUpdate;

        if (!employeeSnapshots.isEmpty()) {
            update employeeSnapshots.values();
        }
    }

    public void finish(Database.BatchableContext context) {
        // No-op.
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new AttendanceAutoCloseBatch(), 200);
    }
}