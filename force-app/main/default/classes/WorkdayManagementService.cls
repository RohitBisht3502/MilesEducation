public with sharing class WorkdayManagementService {
    public class BreakRow {
        @AuraEnabled public Id id;
        @AuraEnabled public DateTime breakStart;
        @AuraEnabled public DateTime breakEnd;
        @AuraEnabled public Decimal durationMinutes;
        @AuraEnabled public String breakStatus;
        @AuraEnabled public Boolean isOpen;
        @AuraEnabled public Integer sequenceNumber;
    }

    public class AttendanceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Date attendanceDate;
        @AuraEnabled public String dayStatus;
        @AuraEnabled public DateTime startTime;
        @AuraEnabled public DateTime endTime;
        @AuraEnabled public Decimal totalBreakMinutes;
        @AuraEnabled public Decimal grossWorkMinutes;
        @AuraEnabled public Decimal netWorkMinutes;
        @AuraEnabled public Decimal grossWorkHours;
        @AuraEnabled public Decimal netWorkHours;
        @AuraEnabled public Boolean autoEnded;
        @AuraEnabled public Boolean isNonBusinessHours;
        @AuraEnabled public Boolean isWeekOff;
        @AuraEnabled public String daySummary;
        @AuraEnabled public String unavailableReason;
        @AuraEnabled public String statusClass;
        @AuraEnabled public String breakTimeline;
    }

    public class DashboardResponse {
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String team;
        @AuraEnabled public Boolean employeeActive;
        @AuraEnabled public String state;
        @AuraEnabled public String stateLabel;
        @AuraEnabled public String motivationalLine;
        @AuraEnabled public AttendanceRow today;
        @AuraEnabled public List<BreakRow> todayBreaks;
        @AuraEnabled public List<AttendanceRow> lastSevenDays;
    }

    private static final String STATE_NOT_STARTED = 'NOT_STARTED';
    private static final String STATE_ACTIVE = 'ACTIVE';
    private static final String STATE_ON_BREAK = 'ON_BREAK';
    private static final String STATE_ENDED = 'ENDED';
    private static final String STATE_LEAVE = 'LEAVE';
    private static final String STATE_INACTIVE = 'INACTIVE';
    private static final String MISSING_TODAY_ATTENDANCE_MESSAGE =
        'We do not have the attendance record for you. Please contact admin to proceed.';

    @AuraEnabled
    public static DashboardResponse loadDashboard() {
        Employee__c employee = getOrCreateEmployee(UserInfo.getUserId());
        Attendance__c todayAttendance = queryTodayAttendance(employee.Id, false);
        List<Break_Time__c> todayBreaks = todayAttendance == null
            ? new List<Break_Time__c>()
            : getBreaksForAttendance(todayAttendance.Id);

        if (todayAttendance != null && todayAttendance.Start_Time__c != null && todayAttendance.End_Time__c == null) {
            WorkdayManagementUtil.recalculateAttendance(todayAttendance, todayBreaks, System.now());
        }

        return buildDashboard(employee, todayAttendance, todayBreaks);
    }

    @AuraEnabled
    public static DashboardResponse startDay() {
        Employee__c employee = getOrCreateEmployee(UserInfo.getUserId());
        if (!employee.Is_Active__c) {
            throw new AuraHandledException('Your employee profile is inactive. Please contact your manager.');
        }

        Attendance__c todayAttendance = getTodayAttendanceRequired(employee, true);
        if (todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_LEAVE) {
            throw new AuraHandledException('You are marked unavailable for today.');
        }
        if (todayAttendance.Start_Time__c != null && todayAttendance.End_Time__c == null) {
            return loadDashboard();
        }
        if (todayAttendance.End_Time__c != null) {
            throw new AuraHandledException('Day is already closed for today.');
        }

        DateTime nowTime = System.now();
        todayAttendance.Start_Time__c = nowTime;
        todayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ACTIVE;
        todayAttendance.Auto_Ended__c = false;
        todayAttendance.Is_Non_Business_Hours__c = !WorkdayManagementUtil.isWithinBusinessWindow(employee, nowTime);
        todayAttendance.Total_Break_Minutes__c = 0;
        todayAttendance.Gross_Work_Minutes__c = 0;
        todayAttendance.Net_Work_Minutes__c = 0;
        update todayAttendance;
        updateEmployeeSnapshot(employee, 'Active', nowTime, null, 'Present');

        return loadDashboard();
    }

    @AuraEnabled
    public static DashboardResponse startBreak() {
        Employee__c employee = getOrCreateEmployee(UserInfo.getUserId());
        Attendance__c todayAttendance = getTodayAttendanceRequired(employee, true);

        validateAttendanceForBreak(todayAttendance);

        Break_Time__c openBreak = getOpenBreak(todayAttendance.Id, true);
        if (openBreak != null) {
            throw new AuraHandledException('A break is already in progress.');
        }

        Integer existingBreakCount = [
            SELECT COUNT()
            FROM Break_Time__c
            WHERE Attendance__c = :todayAttendance.Id
        ];

        Break_Time__c breakEntry = new Break_Time__c();
        breakEntry.Attendance__c = todayAttendance.Id;
        breakEntry.Break_Start__c = System.now();
        breakEntry.Break_Status__c = WorkdayManagementUtil.BREAK_STATUS_IN_PROGRESS;
        breakEntry.Sequence_Number__c = existingBreakCount + 1;
        breakEntry.Started_By__c = UserInfo.getUserId();
        insert breakEntry;

        todayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ON_BREAK;
        update todayAttendance;
        updateEmployeeSnapshot(
            employee,
            'On Break',
            todayAttendance.Start_Time__c,
            null,
            'Present'
        );

        return loadDashboard();
    }

    @AuraEnabled
    public static DashboardResponse endBreak() {
        Employee__c employee = getOrCreateEmployee(UserInfo.getUserId());
        Attendance__c todayAttendance = getTodayAttendanceRequired(employee, true);

        validateAttendanceForBreak(todayAttendance);

        Break_Time__c openBreak = getOpenBreak(todayAttendance.Id, true);
        if (openBreak == null) {
            throw new AuraHandledException('No active break found.');
        }

        DateTime nowTime = System.now();
        openBreak.Break_End__c = nowTime;
        openBreak.Duration_Minutes__c = WorkdayManagementUtil.minutesBetween(openBreak.Break_Start__c, nowTime);
        openBreak.Break_Status__c = WorkdayManagementUtil.BREAK_STATUS_COMPLETED;
        openBreak.Ended_By__c = UserInfo.getUserId();
        update openBreak;

        List<Break_Time__c> breaks = getBreaksForAttendance(todayAttendance.Id);
        todayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ACTIVE;
        WorkdayManagementUtil.recalculateAttendance(todayAttendance, breaks, nowTime);
        update todayAttendance;
        updateEmployeeSnapshot(
            employee,
            'Active',
            todayAttendance.Start_Time__c,
            null,
            'Present'
        );

        return loadDashboard();
    }

    @AuraEnabled
    public static DashboardResponse endDay() {
        Employee__c employee = getOrCreateEmployee(UserInfo.getUserId());
        Attendance__c todayAttendance = getTodayAttendanceRequired(employee, true);

        if (todayAttendance.Start_Time__c == null) {
            throw new AuraHandledException('Day is not started yet.');
        }
        if (todayAttendance.End_Time__c != null) {
            return loadDashboard();
        }
        if (todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_LEAVE) {
            throw new AuraHandledException('Attendance is marked as leave.');
        }

        DateTime nowTime = System.now();
        Break_Time__c openBreak = getOpenBreak(todayAttendance.Id, true);
        if (openBreak != null) {
            openBreak.Break_End__c = nowTime;
            openBreak.Duration_Minutes__c = WorkdayManagementUtil.minutesBetween(openBreak.Break_Start__c, nowTime);
            openBreak.Break_Status__c = WorkdayManagementUtil.BREAK_STATUS_COMPLETED;
            openBreak.Ended_By__c = UserInfo.getUserId();
            update openBreak;
        }

        List<Break_Time__c> breaks = getBreaksForAttendance(todayAttendance.Id);
        todayAttendance.End_Time__c = nowTime;
        todayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ENDED;
        WorkdayManagementUtil.recalculateAttendance(todayAttendance, breaks, nowTime);
        todayAttendance.Day_Summary__c = WorkdayManagementUtil.buildDaySummary(todayAttendance, breaks);
        update todayAttendance;
        updateEmployeeSnapshot(
            employee,
            'Ended',
            todayAttendance.Start_Time__c,
            nowTime,
            'Present'
        );

        return loadDashboard();
    }

    @AuraEnabled
    public static void markUnavailable(Id employeeId, Date attendanceDate, String reason) {
        if (employeeId == null || attendanceDate == null) {
            throw new AuraHandledException('Employee and date are required.');
        }

        List<Attendance__c> existingAttendance = [
            SELECT Id, Start_Time__c, End_Time__c, Day_Status__c, Unique_Key__c, Is_Week_Off__c
            FROM Attendance__c
            WHERE Employee__c = :employeeId
            AND Attendance_Date__c = :attendanceDate
            LIMIT 1
            FOR UPDATE
        ];

        Attendance__c attendance;
        if (existingAttendance.isEmpty()) {
            attendance = new Attendance__c();
            attendance.Employee__c = employeeId;
            attendance.Attendance_Date__c = attendanceDate;
            attendance.Unique_Key__c = WorkdayManagementUtil.buildAttendanceKey(employeeId, attendanceDate);
        } else {
            attendance = existingAttendance[0];
        }

        if (attendance.Start_Time__c != null && attendance.End_Time__c == null) {
            throw new AuraHandledException('Cannot mark unavailable after day has started.');
        }

        attendance.Start_Time__c = null;
        attendance.End_Time__c = null;
        attendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_LEAVE;
        attendance.Unavailable_Marked_By__c = UserInfo.getUserId();
        attendance.Unavailable_Reason__c = reason;
        attendance.Is_Week_Off__c = false;
        attendance.Total_Break_Minutes__c = 0;
        attendance.Gross_Work_Minutes__c = 0;
        attendance.Net_Work_Minutes__c = 0;

        if (attendance.Id == null) {
            insert attendance;
        } else {
            update attendance;
        }

        if (attendanceDate == Date.today()) {
            updateEmployeeSnapshot(
                new Employee__c(Id = employeeId),
                'Leave',
                null,
                null,
                'Absent'
            );
        }
    }

    private static void validateAttendanceForBreak(Attendance__c attendance) {
        if (attendance.Start_Time__c == null) {
            throw new AuraHandledException('Start day before taking a break.');
        }
        if (attendance.End_Time__c != null) {
            throw new AuraHandledException('Day has already ended.');
        }
        if (attendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_LEAVE) {
            throw new AuraHandledException('Attendance is marked as leave.');
        }
    }

    private static DashboardResponse buildDashboard(
        Employee__c employee,
        Attendance__c todayAttendance,
        List<Break_Time__c> todayBreaks
    ) {
        DashboardResponse response = new DashboardResponse();
        response.employeeId = employee.Id;
        response.employeeName = employee.Name;
        response.team = employee.Team__c;
        response.employeeActive = employee.Is_Active__c;
        response.todayBreaks = new List<BreakRow>();

        for (Break_Time__c breakItem : todayBreaks) {
            response.todayBreaks.add(toBreakRow(breakItem));
        }

        String state = deriveState(employee, todayAttendance, todayBreaks);
        response.state = state;
        response.stateLabel = mapStateLabel(state, todayAttendance);
        response.motivationalLine = mapMotivationalLine(state);
        response.today = todayAttendance == null ? null : toAttendanceRow(todayAttendance, todayBreaks);
        response.lastSevenDays = getLastSevenDays(employee.Id);
        return response;
    }

    private static AttendanceRow toAttendanceRow(Attendance__c attendance, List<Break_Time__c> breaks) {
        AttendanceRow row = new AttendanceRow();
        row.id = attendance.Id;
        row.attendanceDate = attendance.Attendance_Date__c;
        row.dayStatus = attendance.Day_Status__c;
        row.startTime = attendance.Start_Time__c;
        row.endTime = attendance.End_Time__c;
        row.totalBreakMinutes = attendance.Total_Break_Minutes__c;
        row.grossWorkMinutes = attendance.Gross_Work_Minutes__c;
        row.netWorkMinutes = attendance.Net_Work_Minutes__c;
        row.grossWorkHours = attendance.Gross_Work_Minutes__c == null
            ? 0
            : (attendance.Gross_Work_Minutes__c / 60).setScale(2);
        row.netWorkHours = attendance.Net_Work_Minutes__c == null
            ? 0
            : (attendance.Net_Work_Minutes__c / 60).setScale(2);
        row.autoEnded = attendance.Auto_Ended__c;
        row.isNonBusinessHours = attendance.Is_Non_Business_Hours__c;
        row.isWeekOff = attendance.Is_Week_Off__c;
        row.daySummary = String.isBlank(attendance.Day_Summary__c)
            ? WorkdayManagementUtil.buildDaySummary(attendance, breaks)
            : attendance.Day_Summary__c;
        row.unavailableReason = attendance.Unavailable_Reason__c;
        row.statusClass = mapStatusClass(attendance.Day_Status__c);
        row.breakTimeline = WorkdayManagementUtil.buildBreakTimeline(breaks);
        return row;
    }

    private static BreakRow toBreakRow(Break_Time__c breakItem) {
        BreakRow row = new BreakRow();
        row.id = breakItem.Id;
        row.breakStart = breakItem.Break_Start__c;
        row.breakEnd = breakItem.Break_End__c;
        row.durationMinutes = breakItem.Duration_Minutes__c;
        row.breakStatus = breakItem.Break_Status__c;
        row.isOpen = breakItem.Break_End__c == null;
        row.sequenceNumber = breakItem.Sequence_Number__c == null
            ? null
            : Integer.valueOf(String.valueOf(breakItem.Sequence_Number__c));
        return row;
    }

    private static List<AttendanceRow> getLastSevenDays(Id employeeId) {
        Date fromDate = Date.today().addDays(-6);
        List<Attendance__c> history = [
            SELECT Id, Attendance_Date__c, Start_Time__c, End_Time__c, Day_Status__c,
                   Auto_Ended__c, Is_Non_Business_Hours__c, Is_Week_Off__c,
                   Unavailable_Reason__c, Day_Summary__c, Total_Break_Minutes__c,
                   Gross_Work_Minutes__c, Net_Work_Minutes__c
            FROM Attendance__c
            WHERE Employee__c = :employeeId
            AND Attendance_Date__c >= :fromDate
            ORDER BY Attendance_Date__c DESC
            LIMIT 7
        ];

        Map<Id, List<Break_Time__c>> breaksByAttendance = new Map<Id, List<Break_Time__c>>();
        Set<Id> attendanceIds = new Set<Id>();
        for (Attendance__c attendance : history) {
            attendanceIds.add(attendance.Id);
            breaksByAttendance.put(attendance.Id, new List<Break_Time__c>());
        }

        if (!attendanceIds.isEmpty()) {
            for (Break_Time__c breakItem : [
                SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c,
                       Break_Status__c, Sequence_Number__c
                FROM Break_Time__c
                WHERE Attendance__c IN :attendanceIds
                ORDER BY Break_Start__c ASC
            ]) {
                breaksByAttendance.get(breakItem.Attendance__c).add(breakItem);
            }
        }

        List<AttendanceRow> rows = new List<AttendanceRow>();
        for (Attendance__c attendance : history) {
            List<Break_Time__c> breaks = breaksByAttendance.get(attendance.Id);
            if (attendance.Start_Time__c != null && attendance.End_Time__c == null) {
                WorkdayManagementUtil.recalculateAttendance(attendance, breaks, System.now());
            }
            rows.add(toAttendanceRow(attendance, breaks));
        }
        return rows;
    }

    private static String deriveState(
        Employee__c employee,
        Attendance__c todayAttendance,
        List<Break_Time__c> todayBreaks
    ) {
        if (employee == null || !employee.Is_Active__c) {
            return STATE_INACTIVE;
        }
        if (todayAttendance == null || todayAttendance.Start_Time__c == null) {
            if (todayAttendance != null && todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_LEAVE) {
                return STATE_LEAVE;
            }
            return STATE_NOT_STARTED;
        }
        if (todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_LEAVE) {
            return STATE_LEAVE;
        }
        if (todayAttendance.End_Time__c != null ||
            todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_ENDED ||
            todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_AUTO_ENDED) {
            return STATE_ENDED;
        }
        if (hasOpenBreak(todayBreaks) || todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_ON_BREAK) {
            return STATE_ON_BREAK;
        }
        return STATE_ACTIVE;
    }

    private static Boolean hasOpenBreak(List<Break_Time__c> breaks) {
        if (breaks == null || breaks.isEmpty()) {
            return false;
        }
        for (Break_Time__c breakItem : breaks) {
            if (breakItem.Break_End__c == null) {
                return true;
            }
        }
        return false;
    }

    private static String mapStateLabel(String state, Attendance__c todayAttendance) {
        if (state == STATE_NOT_STARTED) {
            return 'Not Started';
        }
        if (state == STATE_ACTIVE) {
            return 'Active';
        }
        if (state == STATE_ON_BREAK) {
            return 'On Break';
        }
        if (state == STATE_ENDED) {
            if (todayAttendance != null && todayAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_AUTO_ENDED) {
                return 'Auto Ended';
            }
            return 'Ended';
        }
        if (state == STATE_LEAVE) {
            return 'Leave';
        }
        return 'Inactive';
    }

    private static String mapMotivationalLine(String state) {
        if (state == STATE_NOT_STARTED) {
            return 'Start your day when you are ready. Login alone does not mark attendance.';
        }
        if (state == STATE_ACTIVE) {
            return 'You are active for the day. Keep your momentum going.';
        }
        if (state == STATE_ON_BREAK) {
            return 'Break is running. End break to resume active status.';
        }
        if (state == STATE_ENDED) {
            return 'Day completed. Summary is captured for review.';
        }
        if (state == STATE_LEAVE) {
            return 'You are marked unavailable/leave for today.';
        }
        return 'Employee profile is inactive.';
    }

    private static String mapStatusClass(String dayStatus) {
        if (dayStatus == WorkdayManagementUtil.DAY_STATUS_ACTIVE) {
            return 'status-active';
        }
        if (dayStatus == WorkdayManagementUtil.DAY_STATUS_ON_BREAK) {
            return 'status-break';
        }
        if (dayStatus == WorkdayManagementUtil.DAY_STATUS_PLANNED) {
            return 'status-planned';
        }
        if (dayStatus == WorkdayManagementUtil.DAY_STATUS_LEAVE) {
            return 'status-leave';
        }
        return 'status-ended';
    }

    private static Employee__c getOrCreateEmployee(Id userId) {
        List<Employee__c> employees = [
            SELECT Id, Name, User__c, Team__c, Is_Active__c, Is_Shift_Based__c,
                   Shift_Start_Time__c, Shift_End_Time__c, Weekly_Off_Day__c,
                   Working_Days__c, Business_Hours__c, Current_Day_Status__c,
                   Current_Day_Start__c, Current_Day_End__c, Availability_Status__c
            FROM Employee__c
            WHERE User__c = :userId
            LIMIT 1
        ];
        if (!employees.isEmpty()) {
            return employees[0];
        }

        User currentUser = [
            SELECT Id, Name
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];

        Employee__c employee = new Employee__c();
        employee.Name = currentUser.Name;
        employee.User__c = currentUser.Id;
        employee.Team__c = 'Sales';
        employee.Is_Active__c = true;
        employee.Weekly_Off_Day__c = 'Monday';
        employee.Working_Days__c = 'Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
        employee.Shift_Start_Time__c = Time.newInstance(10, 0, 0, 0);
        employee.Shift_End_Time__c = Time.newInstance(19, 0, 0, 0);
        employee.Current_Day_Status__c = 'Not Started';
        employee.Availability_Status__c = 'Present';
        insert employee;
        return employee;
    }

    private static Attendance__c getTodayAttendanceRequired(Employee__c employee, Boolean forUpdate) {
        Attendance__c attendance = queryTodayAttendance(employee.Id, forUpdate);
        if (attendance == null) {
            throw new AuraHandledException(MISSING_TODAY_ATTENDANCE_MESSAGE);
        }
        return attendance;
    }

    private static Attendance__c queryTodayAttendance(Id employeeId, Boolean forUpdate) {
        Date todayDate = Date.today();
        if (forUpdate) {
            List<Attendance__c> attendanceRows = [
                SELECT Id, Employee__c, Attendance_Date__c, Unique_Key__c, Start_Time__c, End_Time__c,
                       Day_Status__c, Auto_Ended__c, Unavailable_Marked_By__c, Unavailable_Reason__c,
                       Total_Break_Minutes__c, Gross_Work_Minutes__c, Net_Work_Minutes__c,
                       Day_Summary__c, Is_Non_Business_Hours__c, Is_Week_Off__c
                FROM Attendance__c
                WHERE Employee__c = :employeeId
                AND Attendance_Date__c = :todayDate
                LIMIT 1
                FOR UPDATE
            ];
            return attendanceRows.isEmpty() ? null : attendanceRows[0];
        }

        List<Attendance__c> attendanceRows = [
            SELECT Id, Employee__c, Attendance_Date__c, Unique_Key__c, Start_Time__c, End_Time__c,
                   Day_Status__c, Auto_Ended__c, Unavailable_Marked_By__c, Unavailable_Reason__c,
                   Total_Break_Minutes__c, Gross_Work_Minutes__c, Net_Work_Minutes__c,
                   Day_Summary__c, Is_Non_Business_Hours__c, Is_Week_Off__c
            FROM Attendance__c
            WHERE Employee__c = :employeeId
            AND Attendance_Date__c = :todayDate
            LIMIT 1
        ];
        return attendanceRows.isEmpty() ? null : attendanceRows[0];
    }

    private static List<Break_Time__c> getBreaksForAttendance(Id attendanceId) {
        return [
            SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c,
                   Break_Status__c, Sequence_Number__c
            FROM Break_Time__c
            WHERE Attendance__c = :attendanceId
            ORDER BY Sequence_Number__c ASC, Break_Start__c ASC
        ];
    }

    private static Break_Time__c getOpenBreak(Id attendanceId, Boolean forUpdate) {
        if (forUpdate) {
            List<Break_Time__c> latestOpenBreak = [
                SELECT Id
                FROM Break_Time__c
                WHERE Attendance__c = :attendanceId
                AND Break_End__c = null
                ORDER BY Break_Start__c DESC
                LIMIT 1
            ];
            if (latestOpenBreak.isEmpty()) {
                return null;
            }

            List<Break_Time__c> lockedBreakRows = [
                SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c,
                       Break_Status__c, Sequence_Number__c, Started_By__c, Ended_By__c
                FROM Break_Time__c
                WHERE Id = :latestOpenBreak[0].Id
                AND Break_End__c = null
                LIMIT 1
                FOR UPDATE
            ];
            return lockedBreakRows.isEmpty() ? null : lockedBreakRows[0];
        }

        List<Break_Time__c> breakRows = [
            SELECT Id, Attendance__c, Break_Start__c, Break_End__c, Duration_Minutes__c,
                   Break_Status__c, Sequence_Number__c, Started_By__c, Ended_By__c
            FROM Break_Time__c
            WHERE Attendance__c = :attendanceId
            AND Break_End__c = null
            ORDER BY Break_Start__c DESC
            LIMIT 1
        ];
        return breakRows.isEmpty() ? null : breakRows[0];
    }

    private static void updateEmployeeSnapshot(
        Employee__c employee,
        String dayStatus,
        DateTime startTime,
        DateTime endTime,
        String availability
    ) {
        if (employee == null || employee.Id == null) {
            return;
        }

        Employee__c snapshot = new Employee__c();
        snapshot.Id = employee.Id;
        snapshot.Current_Day_Status__c = dayStatus;
        snapshot.Current_Day_Start__c = startTime;
        snapshot.Current_Day_End__c = endTime;
        snapshot.Availability_Status__c = availability;
        update snapshot;
    }
}