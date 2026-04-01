@IsTest
private class AttendanceBatchTest {
    private static final String ATTENDANCE_STATUS_FIELD_PRIMARY = 'Attendance_status__c';
    private static final String ATTENDANCE_STATUS_FIELD_FALLBACK = 'Attendance_Status__c';

    @TestSetup
    static void setupData() {
        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Employee__c employee = new Employee__c();
        employee.Name = 'Batch Test Employee';
        employee.User__c = currentUser.Id;
        employee.Team__c = 'Sales';
        employee.Is_Active__c = true;
        employee.Weekly_Off_Day__c = 'Monday';
        employee.Working_Days__c = 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
        employee.Shift_Start_Time__c = Time.newInstance(10, 0, 0, 0);
        employee.Shift_End_Time__c = Time.newInstance(19, 0, 0, 0);
        insert employee;
    }

    @IsTest
    static void testMonthlySeederCreatesTodayRecordOnly() {
        Employee__c employee = [SELECT Id, User__c FROM Employee__c LIMIT 1];
        Date todayDate = Date.today();

        Test.startTest();
        Database.executeBatch(new AttendanceMonthlySeederBatch(), 1);
        Database.executeBatch(new AttendanceMonthlySeederBatch(), 1);
        Test.stopTest();

        List<Attendance__c> attendanceRows = [
            SELECT Id, Attendance_Date__c, Day_Status__c, OwnerId
            FROM Attendance__c
            WHERE Employee__c = :employee.Id
            AND Attendance_Date__c = :todayDate
        ];

        System.assertEquals(1, attendanceRows.size(), 'Seeder must create one attendance row for today.');
        System.assertEquals(todayDate, attendanceRows[0].Attendance_Date__c, 'Attendance date should be today.');
        System.assertNotEquals(null, attendanceRows[0].Day_Status__c, 'Day status should be populated.');
        System.assertEquals(employee.User__c, attendanceRows[0].OwnerId, 'Attendance owner should come from employee sales user mapping.');
    }

    @IsTest
    static void testAutoCloseBatchClosesOpenAttendanceAndBreak() {
        Employee__c employee = [SELECT Id FROM Employee__c LIMIT 1];
        Date attendanceDate = Date.today().addDays(-1);

        Attendance__c attendance = new Attendance__c();
        attendance.Employee__c = employee.Id;
        attendance.Attendance_Date__c = attendanceDate;
        attendance.Unique_Key__c = WorkdayManagementUtil.buildAttendanceKey(employee.Id, attendanceDate);
        attendance.Start_Time__c = DateTime.newInstance(attendanceDate, Time.newInstance(10, 0, 0, 0));
        attendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ACTIVE;
        insert attendance;

        Break_Time__c breakEntry = new Break_Time__c();
        breakEntry.Attendance__c = attendance.Id;
        breakEntry.Break_Start__c = DateTime.newInstance(attendanceDate, Time.newInstance(18, 0, 0, 0));
        breakEntry.Break_Status__c = WorkdayManagementUtil.BREAK_STATUS_IN_PROGRESS;
        breakEntry.Sequence_Number__c = 1;
        insert breakEntry;

        Test.startTest();
        Database.executeBatch(new AttendanceAutoCloseBatch(), 1);
        Test.stopTest();

        Attendance__c refreshedAttendance = [
            SELECT End_Time__c, Day_Status__c, Auto_Ended__c, Day_Summary__c, Net_Work_Minutes__c
            FROM Attendance__c
            WHERE Id = :attendance.Id
            LIMIT 1
        ];

        Break_Time__c refreshedBreak = [
            SELECT Break_End__c, Break_Status__c, Auto_Ended__c, Duration_Minutes__c, Ended_By__c
            FROM Break_Time__c
            WHERE Id = :breakEntry.Id
            LIMIT 1
        ];

        DateTime expectedEnd = DateTime.newInstance(attendanceDate, Time.newInstance(23, 0, 0, 0));
        System.assertEquals(expectedEnd, refreshedAttendance.End_Time__c, 'Attendance end must be forced to 11 PM.');
        System.assertEquals(WorkdayManagementUtil.DAY_STATUS_AUTO_ENDED, refreshedAttendance.Day_Status__c);
        System.assertEquals(true, refreshedAttendance.Auto_Ended__c);
        System.assertNotEquals(null, refreshedAttendance.Day_Summary__c);
        System.assert(refreshedAttendance.Net_Work_Minutes__c >= 0);

        System.assertEquals(expectedEnd, refreshedBreak.Break_End__c, 'Open break must end at 11 PM.');
        System.assertEquals(WorkdayManagementUtil.BREAK_STATUS_AUTO_ENDED, refreshedBreak.Break_Status__c);
        System.assertEquals(true, refreshedBreak.Auto_Ended__c);
        System.assertEquals(UserInfo.getUserId(), refreshedBreak.Ended_By__c, 'Auto-ended break should store batch updater user.');
        System.assert(refreshedBreak.Duration_Minutes__c > 0);

        String attendanceStatusField = getAttendanceStatusFieldApiName();
        if (attendanceStatusField != null) {
            Id attendanceId = attendance.Id;
            List<Attendance__c> statusRows = (List<Attendance__c>) Database.query(
                'SELECT Id, ' + attendanceStatusField +
                ' FROM Attendance__c WHERE Id = :attendanceId LIMIT 1'
            );
            Attendance__c statusRow = statusRows[0];
            System.assertEquals('Half Day', (String) statusRow.get(attendanceStatusField));
        }
    }

    @IsTest
    static void testAutoCloseBatchAssignsAttendanceStatusForClosedAndAutoClosed() {
        String attendanceStatusField = getAttendanceStatusFieldApiName();
        if (attendanceStatusField == null) {
            return;
        }

        Employee__c employee = [SELECT Id FROM Employee__c LIMIT 1];
        Date halfDayDate = Date.today().addDays(-5);
        Date fullDayDate = Date.today().addDays(-4);
        Date autoCloseDate = Date.today().addDays(-3);

        Attendance__c halfDayAttendance = new Attendance__c();
        halfDayAttendance.Employee__c = employee.Id;
        halfDayAttendance.Attendance_Date__c = halfDayDate;
        halfDayAttendance.Unique_Key__c = WorkdayManagementUtil.buildAttendanceKey(employee.Id, halfDayDate);
        halfDayAttendance.Start_Time__c = DateTime.newInstance(halfDayDate, Time.newInstance(10, 0, 0, 0));
        halfDayAttendance.End_Time__c = DateTime.newInstance(halfDayDate, Time.newInstance(16, 0, 0, 0));
        halfDayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ENDED;
        halfDayAttendance.Total_Break_Minutes__c = 0;
        halfDayAttendance.Gross_Work_Minutes__c = 360;
        halfDayAttendance.Net_Work_Minutes__c = 360;

        Attendance__c fullDayAttendance = new Attendance__c();
        fullDayAttendance.Employee__c = employee.Id;
        fullDayAttendance.Attendance_Date__c = fullDayDate;
        fullDayAttendance.Unique_Key__c = WorkdayManagementUtil.buildAttendanceKey(employee.Id, fullDayDate);
        fullDayAttendance.Start_Time__c = DateTime.newInstance(fullDayDate, Time.newInstance(9, 0, 0, 0));
        fullDayAttendance.End_Time__c = DateTime.newInstance(fullDayDate, Time.newInstance(19, 0, 0, 0));
        fullDayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ENDED;
        fullDayAttendance.Total_Break_Minutes__c = 0;
        fullDayAttendance.Gross_Work_Minutes__c = 600;
        fullDayAttendance.Net_Work_Minutes__c = 600;

        Attendance__c autoCloseAttendance = new Attendance__c();
        autoCloseAttendance.Employee__c = employee.Id;
        autoCloseAttendance.Attendance_Date__c = autoCloseDate;
        autoCloseAttendance.Unique_Key__c = WorkdayManagementUtil.buildAttendanceKey(employee.Id, autoCloseDate);
        autoCloseAttendance.Start_Time__c = DateTime.newInstance(autoCloseDate, Time.newInstance(13, 0, 0, 0));
        autoCloseAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_ACTIVE;

        insert new List<Attendance__c>{ halfDayAttendance, fullDayAttendance, autoCloseAttendance };

        Test.startTest();
        Database.executeBatch(new AttendanceAutoCloseBatch(), 1);
        Test.stopTest();

        Set<Id> attendanceIds = new Set<Id>{ halfDayAttendance.Id, fullDayAttendance.Id, autoCloseAttendance.Id };
        List<Attendance__c> refreshedRows = (List<Attendance__c>) Database.query(
            'SELECT Id, End_Time__c, Day_Status__c, Auto_Ended__c, Net_Work_Minutes__c, ' + attendanceStatusField +
            ' FROM Attendance__c WHERE Id IN :attendanceIds'
        );
        Map<Id, Attendance__c> attendanceById = new Map<Id, Attendance__c>(refreshedRows);

        System.assertEquals('Half Day', (String) attendanceById.get(halfDayAttendance.Id).get(attendanceStatusField));
        System.assertEquals('Full Day', (String) attendanceById.get(fullDayAttendance.Id).get(attendanceStatusField));

        Attendance__c refreshedAutoClose = attendanceById.get(autoCloseAttendance.Id);
        DateTime expectedAutoCloseEnd = DateTime.newInstance(autoCloseDate, Time.newInstance(23, 0, 0, 0));
        System.assertEquals(expectedAutoCloseEnd, refreshedAutoClose.End_Time__c);
        System.assertEquals(WorkdayManagementUtil.DAY_STATUS_AUTO_ENDED, refreshedAutoClose.Day_Status__c);
        System.assertEquals(true, refreshedAutoClose.Auto_Ended__c);
        System.assertEquals('Full Day', (String) refreshedAutoClose.get(attendanceStatusField));
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