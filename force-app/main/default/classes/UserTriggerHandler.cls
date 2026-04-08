public without sharing class UserTriggerHandler {
    public static void createEmployeeAndAttendance(List<User> newUsers) {
        if (newUsers == null || newUsers.isEmpty()) {
            return;
        }

        //Set<String> userEmailsForQuery = new Set<String>();
        Set<Id> userIdsForQuery = new Set<Id>();
        for (User u : newUsers) {
            /*if (!String.isBlank(u.Email)) {
                userEmailsForQuery.add(u.Email.trim());
            }*/
            if (u.Id != null) {
                userIdsForQuery.add(u.Id);
            }
        }

        //Set<String> existingEmployeeEmails = new Set<String>();
        Set<Id> existingEmployeeUserIds = new Set<Id>();
        /*for (Employee__c existingEmp : [
            SELECT Id, User__r.Email
            FROM Employee__c
            WHERE User__r.Email IN :userEmailsForQuery
        ]) {
            if (existingEmp.User__r != null && !String.isBlank(existingEmp.User__r.Email)) {
                existingEmployeeEmails.add(existingEmp.User__r.Email.trim().toLowerCase());
            }
        }*/
        for (Employee__c existingEmp : [
            SELECT Id, User__c
            FROM Employee__c
            WHERE User__c IN :userIdsForQuery
        ]) {
            if (existingEmp.User__c != null) {
                existingEmployeeUserIds.add(existingEmp.User__c);
            }
        }
        
        // Get all working days except Sunday
        String workingDays = getWorkingDaysExceptSunday();
        
        // List to store Employee records
        List<Employee__c> employees = new List<Employee__c>();
        
        // Create Employee records from Users
        for(User u : newUsers) {
            /*String emailKey = u.Email == null ? null : u.Email.trim().toLowerCase();
            if (String.isBlank(emailKey) || existingEmployeeEmails.contains(emailKey)) {
                continue;
            }*/
            // Changed: Check based on User Id instead of Email
            if (u.Id == null || existingEmployeeUserIds.contains(u.Id)) {
                continue;
            }

            Employee__c emp = new Employee__c();
            String firstName = String.isBlank(u.FirstName) ? '' : u.FirstName.trim();
            String lastName = String.isBlank(u.LastName) ? '' : u.LastName.trim();
            String fullName = (firstName + ' ' + lastName).trim();
            emp.Name = String.isBlank(fullName) ? ('Employee ' + String.valueOf(u.Id)) : fullName;
            emp.User__c = u.Id;
            emp.OwnerId = u.Id;
            emp.Is_Active__c = true;
            emp.Working_Days__c = workingDays;
            System.debug('Employee Name is :::: '+ emp.Name);
            employees.add(emp);
            //existingEmployeeEmails.add(emailKey);
            existingEmployeeUserIds.add(u.Id);
        }
        
        // Insert Employees
        if(!employees.isEmpty()) {
            insert employees;
            
            // List to store Attendance records
            List<Attendance__c> attendances = new List<Attendance__c>();
            
            // Create Attendance records from Employees
            for(Employee__c emp : employees) {
                Attendance__c att = new Attendance__c();
                att.Employee__c = emp.Id;
                att.Attendance_Date__c = Date.today();
                att.Day_Status__c = 'Planned';
                // Convert Date to DateTime and format with Indian timezone
                DateTime dt = DateTime.newInstance(att.Attendance_Date__c, Time.newInstance(0, 0, 0, 0));
                String indianDate = dt.format('dd/MM/yyyy', 'Asia/Kolkata');
                att.Unique_Key__c = String.valueOf(emp.Id) + '-' + indianDate;
                attendances.add(att);
            }
            
            // Insert Attendances
            if(!attendances.isEmpty()) {
                insert attendances;
            }
        }
    }
    
    // Helper method to get working days
    private static String getWorkingDaysExceptSunday() {
        return 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday';
    }
}