@IsTest
private class WorkdayManagementServiceTest {
    @TestSetup
    static void setupData() {
        User currentUser = [
            SELECT Id, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Employee__c employee = new Employee__c();
        employee.Name = currentUser.Name;
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
    static void testStartBreakEndFlow() {
        Employee__c employee = [
            SELECT Id
            FROM Employee__c
            WHERE User__c = :UserInfo.getUserId()
            LIMIT 1
        ];

        Date todayDate = Date.today();
        Attendance__c todayAttendance = new Attendance__c();
        todayAttendance.Employee__c = employee.Id;
        todayAttendance.Attendance_Date__c = todayDate;
        todayAttendance.Unique_Key__c = WorkdayManagementUtil.buildAttendanceKey(employee.Id, todayDate);
        todayAttendance.Day_Status__c = WorkdayManagementUtil.DAY_STATUS_PLANNED;
        todayAttendance.Is_Week_Off__c = false;
        todayAttendance.Total_Break_Minutes__c = 0;
        todayAttendance.Gross_Work_Minutes__c = 0;
        todayAttendance.Net_Work_Minutes__c = 0;
        insert todayAttendance;

        Test.startTest();
        WorkdayManagementService.DashboardResponse initialState = WorkdayManagementService.loadDashboard();
        System.assertEquals('NOT_STARTED', initialState.state, 'Initial state should be not started.');

        WorkdayManagementService.DashboardResponse started = WorkdayManagementService.startDay();
        System.assertEquals('ACTIVE', started.state, 'State should move to active after start day.');
        System.assertNotEquals(null, started.today.startTime, 'Start time should be populated.');

        WorkdayManagementService.DashboardResponse onBreak = WorkdayManagementService.startBreak();
        System.assertEquals('ON_BREAK', onBreak.state, 'State should be on break.');
        System.assertEquals(1, onBreak.todayBreaks.size(), 'One break should exist.');

        WorkdayManagementService.DashboardResponse resumed = WorkdayManagementService.endBreak();
        System.assertEquals('ACTIVE', resumed.state, 'State should move back to active after break end.');

        WorkdayManagementService.DashboardResponse ended = WorkdayManagementService.endDay();
        Test.stopTest();

        System.assertEquals('ENDED', ended.state, 'State should be ended after end day.');
        System.assertNotEquals(null, ended.today.endTime, 'End time should be set.');
        System.assert(ended.today.netWorkMinutes >= 0, 'Net minutes should be calculated.');
        System.assert(ended.lastSevenDays.size() > 0, 'History should return rows.');
    }

    @IsTest
    static void testStartDayThrowsWhenTodayAttendanceMissing() {
        Test.startTest();
        try {
            WorkdayManagementService.startDay();
            System.assert(false, 'Start day should fail when attendance is not seeded for today.');
        } catch (AuraHandledException ex) {
            System.assertEquals(
                'We do not have the attendance record for you. Please contact admin to proceed.',
                ex.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkUnavailable() {
        Employee__c employee = [
            SELECT Id
            FROM Employee__c
            WHERE User__c = :UserInfo.getUserId()
            LIMIT 1
        ];

        Date leaveDate = Date.today().addDays(1);

        Test.startTest();
        WorkdayManagementService.markUnavailable(employee.Id, leaveDate, 'Planned leave');
        Test.stopTest();

        Attendance__c attendance = [
            SELECT Day_Status__c, Unavailable_Reason__c, Start_Time__c, End_Time__c
            FROM Attendance__c
            WHERE Employee__c = :employee.Id
            AND Attendance_Date__c = :leaveDate
            LIMIT 1
        ];

        System.assertEquals(WorkdayManagementUtil.DAY_STATUS_LEAVE, attendance.Day_Status__c);
        System.assertEquals('Planned leave', attendance.Unavailable_Reason__c);
        System.assertEquals(null, attendance.Start_Time__c);
        System.assertEquals(null, attendance.End_Time__c);
    }

    @IsTest
    static void testLoadDashboardThrowsWhenEmployeeProfileMissing() {
        User templateUser = [
            SELECT ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        String uniqueToken = String.valueOf(System.now().getTime());
        User noEmployeeUser = new User(
            FirstName = 'No',
            LastName = 'Employee',
            Alias = 'noemp',
            Email = 'no-employee-' + uniqueToken + '@example.com',
            Username = 'no-employee-' + uniqueToken + '@example.com',
            ProfileId = templateUser.ProfileId,
            TimeZoneSidKey = templateUser.TimeZoneSidKey,
            LocaleSidKey = templateUser.LocaleSidKey,
            EmailEncodingKey = templateUser.EmailEncodingKey,
            LanguageLocaleKey = templateUser.LanguageLocaleKey
        );
        insert noEmployeeUser;

        Test.startTest();
        System.runAs(noEmployeeUser) {
            try {
                WorkdayManagementService.loadDashboard();
                System.assert(false, 'Load dashboard should fail when employee profile is missing.');
            } catch (AuraHandledException ex) {
                System.assertEquals(
                    'We do not have your employee profile in the system. Please contact admin for further process.',
                    ex.getMessage()
                );
            }
        }
        Test.stopTest();
    }
}