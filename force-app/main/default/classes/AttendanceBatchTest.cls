@IsTest
private class AttendanceBatchTest {
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
        Employee__c employee = [SELECT Id FROM Employee__c LIMIT 1];
        Date todayDate = Date.today();

        Test.startTest();
        Database.executeBatch(new AttendanceMonthlySeederBatch(), 1);
        Database.executeBatch(new AttendanceMonthlySeederBatch(), 1);
        Test.stopTest();

        List<Attendance__c> attendanceRows = [
            SELECT Id, Attendance_Date__c, Day_Status__c
            FROM Attendance__c
            WHERE Employee__c = :employee.Id
            AND Attendance_Date__c = :todayDate
        ];

        System.assertEquals(1, attendanceRows.size(), 'Seeder must create one attendance row for today.');
        System.assertEquals(todayDate, attendanceRows[0].Attendance_Date__c, 'Attendance date should be today.');
        System.assertNotEquals(null, attendanceRows[0].Day_Status__c, 'Day status should be populated.');
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
            SELECT Break_End__c, Break_Status__c, Auto_Ended__c, Duration_Minutes__c
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
        System.assert(refreshedBreak.Duration_Minutes__c > 0);
    }
}