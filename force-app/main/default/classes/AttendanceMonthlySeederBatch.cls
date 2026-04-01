public with sharing class AttendanceMonthlySeederBatch implements Database.Batchable<SObject>, Schedulable {
    private static final String EMPLOYEE_SALES_USER_FIELD = 'Sales_User__c';
    private static final String EMPLOYEE_USER_FIELD = 'User__c';

    public Database.QueryLocator start(Database.BatchableContext context) {
        List<String> selectFields = new List<String>{
            'Id',
            'Is_Active__c',
            'Working_Days__c',
            'Weekly_Off_Day__c'
        };
        for (String ownerFieldApiName : getEmployeeOwnerFieldApiNames()) {
            selectFields.add(ownerFieldApiName);
        }

        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Employee__c WHERE Is_Active__c = true';
        return Database.getQueryLocator(soql);
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

        Date attendanceDate = Date.today();

        Set<String> existingKeys = new Set<String>();
        for (Attendance__c existingAttendance : [
            SELECT Unique_Key__c
            FROM Attendance__c
            WHERE Employee__c IN :employeeIds
            AND Attendance_Date__c = :attendanceDate
        ]) {
            if (String.isNotBlank(existingAttendance.Unique_Key__c)) {
                existingKeys.add(existingAttendance.Unique_Key__c);
            }
        }

        List<Attendance__c> recordsToInsert = new List<Attendance__c>();
        for (Employee__c employee : employees) {
            String keyValue = WorkdayManagementUtil.buildAttendanceKey(employee.Id, attendanceDate);
            if (existingKeys.contains(keyValue)) {
                continue;
            }

            Boolean isWorking = WorkdayManagementUtil.isWorkingDay(employee, attendanceDate);
            Attendance__c record = new Attendance__c();
            record.Employee__c = employee.Id;
            record.Attendance_Date__c = attendanceDate;
            record.Unique_Key__c = keyValue;
            record.Day_Status__c = isWorking
                ? WorkdayManagementUtil.DAY_STATUS_PLANNED
                : WorkdayManagementUtil.DAY_STATUS_LEAVE;
            record.Is_Week_Off__c = !isWorking;
            record.Total_Break_Minutes__c = 0;
            record.Gross_Work_Minutes__c = 0;
            record.Net_Work_Minutes__c = 0;

            Id ownerId = resolveAttendanceOwnerId(employee);
            if (ownerId != null) {
                record.OwnerId = ownerId;
            }

            recordsToInsert.add(record);
            existingKeys.add(keyValue);
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

    private static Set<String> getEmployeeOwnerFieldApiNames() {
        Map<String, Schema.SObjectField> employeeFieldMap = Schema.SObjectType.Employee__c.fields.getMap();
        Set<String> ownerFieldApiNames = new Set<String>();
        if (employeeFieldMap.containsKey(EMPLOYEE_SALES_USER_FIELD)) {
            ownerFieldApiNames.add(EMPLOYEE_SALES_USER_FIELD);
        }
        if (employeeFieldMap.containsKey(EMPLOYEE_USER_FIELD)) {
            ownerFieldApiNames.add(EMPLOYEE_USER_FIELD);
        }
        return ownerFieldApiNames;
    }

    private static Id resolveAttendanceOwnerId(Employee__c employee) {
        Id salesUserId = getLookupId(employee, EMPLOYEE_SALES_USER_FIELD);
        if (salesUserId != null) {
            return salesUserId;
        }
        return getLookupId(employee, EMPLOYEE_USER_FIELD);
    }

    private static Id getLookupId(Employee__c employee, String fieldApiName) {
        if (employee == null || String.isBlank(fieldApiName)) {
            return null;
        }

        Map<String, Object> populatedFieldMap = employee.getPopulatedFieldsAsMap();
        if (!populatedFieldMap.containsKey(fieldApiName)) {
            return null;
        }

        Object fieldValue = populatedFieldMap.get(fieldApiName);
        return fieldValue == null ? null : (Id) fieldValue;
    }
}