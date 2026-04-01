public without sharing class AttendanceTriggerHelperClass {
    
    public static void handleBeforeUpdate(Map<Id, Attendance__c> oldMap, Map<Id, Attendance__c> newMap) {

        Id currentUserId = UserInfo.getUserId();
        List<Attendance__c> statusChangedAttendance = new List<Attendance__c>();
        Set<Id> employeeIds = new Set<Id>();
        
        for (Attendance__c newAttendance : newMap.values()) {
            Attendance__c oldAttendance = oldMap.get(newAttendance.Id);
            if (oldAttendance == null ||
                oldAttendance.Day_Status__c == newAttendance.Day_Status__c ||
                newAttendance.Employee__c == null) {
                continue;
            }

            statusChangedAttendance.add(newAttendance);
            employeeIds.add(newAttendance.Employee__c);
        }
        
        // If no records to process, exit
        if (statusChangedAttendance.isEmpty()) {
            return;
        }
        
        // Get employee records with user and manager information
        Map<Id, Employee__c> employeeMap = new Map<Id, Employee__c>(
            [SELECT Id, User__c, User__r.ManagerId 
             FROM Employee__c 
             WHERE Id IN :employeeIds]
        );
        
        // Process each attendance record
        for (Attendance__c attendance : statusChangedAttendance) {
            Attendance__c oldAttendance = oldMap.get(attendance.Id);
            Employee__c employee = employeeMap.get(attendance.Employee__c);
            
            // Restrict only when current user is manager of the attendance employee's user.
            if (employee == null ||
                employee.User__c == null ||
                employee.User__r == null ||
                currentUserId != employee.User__r.ManagerId) {
                continue;
            }

            if (!isAllowedDayStatusTransition(oldAttendance.Day_Status__c, attendance.Day_Status__c)) {
                attendance.addError('Day Status can only be changed between Planned and Leave.');
                continue;
            }

            if (oldAttendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_LEAVE &&
                attendance.Day_Status__c == WorkdayManagementUtil.DAY_STATUS_PLANNED) {
                attendance.Unavailable_Marked_By__c = currentUserId;
            }
        }
    }

    private static Boolean isAllowedDayStatusTransition(String oldStatus, String newStatus) {
        return
            (oldStatus == WorkdayManagementUtil.DAY_STATUS_PLANNED &&
             newStatus == WorkdayManagementUtil.DAY_STATUS_LEAVE) ||
            (oldStatus == WorkdayManagementUtil.DAY_STATUS_LEAVE &&
             newStatus == WorkdayManagementUtil.DAY_STATUS_PLANNED);
    }
    
    public static void shareWithManagers(List<Attendance__c> attendanceRecords) {
        
        // Step 1: Collect all Employee IDs from the newly created Attendance records
        Set<Id> employeeIds = new Set<Id>();
        Map<Id, Attendance__c> attendanceByEmployeeId = new Map<Id, Attendance__c>();
        
        for (Attendance__c attendance : attendanceRecords) {
            if (attendance.Employee__c != null) {
                employeeIds.add(attendance.Employee__c);
                attendanceByEmployeeId.put(attendance.Employee__c, attendance);
            }
        }
        
        // If no employees found, exit
        if (employeeIds.isEmpty()) {
            return;
        }
        
        // Step 2: Query Employee records with their User and Manager information
        Map<Id, Employee__c> employeeMap = new Map<Id, Employee__c>(
            [SELECT Id, User__c, User__r.ManagerId 
             FROM Employee__c 
             WHERE Id IN :employeeIds AND User__r.ManagerId != null]
        );
        
        // Step 3: Prepare sharing records
        List<Attendance__Share> sharingRecords = new List<Attendance__Share>();
        
        // Step 4: Create sharing records for each attendance
        for (Employee__c employee : employeeMap.values()) {
            Attendance__c relatedAttendance = attendanceByEmployeeId.get(employee.Id);
            
            if (relatedAttendance != null && employee.User__r.ManagerId != null) {
                
                // Create sharing record
                Attendance__Share share = new Attendance__Share();
                share.ParentId = relatedAttendance.Id;
                share.UserOrGroupId = employee.User__r.ManagerId;
                share.AccessLevel = 'edit'; // Read/Edit access
                share.RowCause = Schema.Attendance__Share.RowCause.Manual; // Manual sharing cause
                
                sharingRecords.add(share);
            }
        }
        
        // Step 5: Insert sharing records if any
        if (!sharingRecords.isEmpty()) {
            try {
                insert sharingRecords;
                System.debug('Successfully shared ' + sharingRecords.size() + ' attendance records with managers');
            } catch (DmlException e) {
                System.debug('Error sharing attendance records: ' + e.getMessage());
                // Handle error appropriately
            }
        }
    }
    
}