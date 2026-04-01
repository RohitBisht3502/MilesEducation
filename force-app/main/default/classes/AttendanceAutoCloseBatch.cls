public with sharing class AttendanceAutoCloseBatch implements Database.Batchable<SObject>, Schedulable {
    private static final String ATTENDANCE_STATUS_FIELD_PRIMARY = 'Attendance_status__c';
    private static final String ATTENDANCE_STATUS_FIELD_FALLBACK = 'Attendance_Status__c';
    private static final String ATTENDANCE_STATUS_HALF_DAY = 'Half Day';
    private static final String ATTENDANCE_STATUS_FULL_DAY = 'Full Day';

    public Database.QueryLocator start(Database.BatchableContext context) {
        Date todayDate = Date.today();
        String attendanceStatusField = getAttendanceStatusFieldApiName();
        String query =
            'SELECT Id, Employee__c, Attendance_Date__c, Start_Time__c, End_Time__c, Day_Status__c, ' +
            'Auto_Ended__c, Total_Break_Minutes__c, Gross_Work_Minutes__c, Net_Work_Minutes__c, ' +
            'Net_Work_Hours__c, Day_Summary__c, Is_Non_Business_Hours__c, Is_Week_Off__c';
        if (attendanceStatusField != null) {
            query += ', ' + attendanceStatusField;
        }
        query += ' FROM Attendance__c WHERE Start_Time__c != null AND Attendance_Date__c = :todayDate';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }

        List<Attendance__c> attendanceScope = (List<Attendance__c>) scope;
        Map<Id, Attendance__c> attendanceToPersistById = new Map<Id, Attendance__c>();
        Map<Id, DateTime> forcedEndByAttendance = new Map<Id, DateTime>();
        Map<Id, Employee__c> employeeSnapshots = new Map<Id, Employee__c>();

        for (Attendance__c attendance : attendanceScope) {
            if (attendance.End_Time__c != null) {
                continue;
            }

            Date dateValue = attendance.Attendance_Date__c == null ? Date.today() : attendance.Attendance_Date__c;
            DateTime forcedEnd = DateTime.newInstance(dateValue, Time.newInstance(23, 0, 0, 0));

            // Skip current-day records if batch runs before 11 PM.
            if (dateValue == Date.today() && forcedEnd > System.now()) {
                continue;
            }

            attendance.End_Time__c = forcedEnd;
            attendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_AUTO_ENDED;
            attendance.Auto_Ended__c = true;
            attendanceToPersistById.put(attendance.Id, attendance);
            forcedEndByAttendance.put(attendance.Id, forcedEnd);

            if (dateValue == Date.today() && attendance.Employee__c != null) {
                Employee__c employeeUpdate = new Employee__c();
                employeeUpdate.Id = attendance.Employee__c;
                employeeUpdate.Current_Day_Status__c = 'Ended';
                employeeUpdate.Current_Day_End__c = forcedEnd;
                employeeSnapshots.put(employeeUpdate.Id, employeeUpdate);
            }
        }

        if (!forcedEndByAttendance.isEmpty()) {
            Set<Id> attendanceIds = forcedEndByAttendance.keySet();
            List<Break_Time__c> openBreaks = [
                SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c, Break_Status__c,
                       Sequence_Number__c, Auto_Ended__c, Ended_By__c
                FROM Break_Time__c
                WHERE Attendance__c IN :attendanceIds
                AND Break_End__c = null
            ];

            Id batchUserId = UserInfo.getUserId();
            for (Break_Time__c breakItem : openBreaks) {
                DateTime forcedEnd = forcedEndByAttendance.get(breakItem.Attendance__c);
                if (forcedEnd == null) {
                    continue;
                }
                breakItem.Break_End__c = forcedEnd;
                breakItem.Duration_Minutes__c = WorkdayManagementUtil.minutesBetween(breakItem.Break_Start__c, forcedEnd);
                breakItem.Break_Status__c = WorkdayManagementUtil.BREAK_STATUS_AUTO_ENDED;
                breakItem.Auto_Ended__c = true;
                breakItem.Ended_By__c = batchUserId;
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

            for (Id attendanceId : attendanceIds) {
                Attendance__c attendance = attendanceToPersistById.get(attendanceId);
                if (attendance == null) {
                    continue;
                }
                List<Break_Time__c> breaks = breaksByAttendance.get(attendanceId);
                WorkdayManagementUtil.recalculateAttendance(attendance, breaks, attendance.End_Time__c);
                attendance.Day_Summary__c = WorkdayManagementUtil.buildDaySummary(attendance, breaks);
            }
        }

        String attendanceStatusField = getAttendanceStatusFieldApiName();
        if (attendanceStatusField != null) {
            for (Attendance__c attendanceScopeRow : attendanceScope) {
                Attendance__c attendance = attendanceToPersistById.containsKey(attendanceScopeRow.Id)
                    ? attendanceToPersistById.get(attendanceScopeRow.Id)
                    : attendanceScopeRow;

                if (attendance.End_Time__c == null) {
                    continue;
                }

                String targetStatus = resolveAttendanceStatus(resolveNetWorkHours(attendance));
                String currentStatus = (String) attendanceScopeRow.get(attendanceStatusField);
                if (targetStatus == currentStatus) {
                    continue;
                }

                Attendance__c updateRow = attendanceToPersistById.containsKey(attendance.Id)
                    ? attendanceToPersistById.get(attendance.Id)
                    : new Attendance__c(Id = attendance.Id);
                updateRow.put(attendanceStatusField, targetStatus);
                attendanceToPersistById.put(updateRow.Id, updateRow);
            }
        }

        if (!attendanceToPersistById.isEmpty()) {
            update attendanceToPersistById.values();
        }

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

    private static Decimal resolveNetWorkHours(Attendance__c attendance) {
        if (attendance == null) {
            return null;
        }
        if (attendance.Net_Work_Minutes__c != null) {
            return (attendance.Net_Work_Minutes__c / 60).setScale(2);
        }
        return attendance.Net_Work_Hours__c;
    }

    private static String resolveAttendanceStatus(Decimal netWorkHours) {
        if (netWorkHours == null) {
            return null;
        }
        if (netWorkHours > 9) {
            return ATTENDANCE_STATUS_FULL_DAY;
        }
        if (netWorkHours > 5 && netWorkHours < 9) {
            return ATTENDANCE_STATUS_HALF_DAY;
        }
        return null;
    }

    private static String getAttendanceStatusFieldApiName() {
        Map<String, Schema.SObjectField> attendanceFieldMap = Schema.SObjectType.Attendance__c.fields.getMap();
        if (attendanceFieldMap.containsKey(ATTENDANCE_STATUS_FIELD_PRIMARY)) {
            return ATTENDANCE_STATUS_FIELD_PRIMARY;
        }
        if (attendanceFieldMap.containsKey(ATTENDANCE_STATUS_FIELD_FALLBACK)) {
            return ATTENDANCE_STATUS_FIELD_FALLBACK;
        }
        return null;
    }
}