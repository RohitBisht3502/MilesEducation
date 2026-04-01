public without sharing class UserTriggerHandler {
    public static void createEmployeeAndAttendance(List<User> newUsers) {
        // Query all active users in the org and process only users with email.
        // Duplicate check is handled using existing Employee__c records tied to User email.
        List<User> usersToProcess = [
            SELECT Id, FirstName, LastName, Email
            FROM User
            WHERE IsActive = true AND Email != null
        ];

        if (usersToProcess.isEmpty()) {
            return;
        }

        Set<String> userEmailsForQuery = new Set<String>();
        for (User u : usersToProcess) {
            if (!String.isBlank(u.Email)) {
                userEmailsForQuery.add(u.Email.trim());
            }
        }

        Set<String> existingEmployeeEmails = new Set<String>();
        for (Employee__c existingEmp : [
            SELECT Id, User__r.Email
            FROM Employee__c
            WHERE User__r.Email IN :userEmailsForQuery
        ]) {
            if (existingEmp.User__r != null && !String.isBlank(existingEmp.User__r.Email)) {
                existingEmployeeEmails.add(existingEmp.User__r.Email.trim().toLowerCase());
            }
        }
        
        // Get all working days except Sunday
        String workingDays = getWorkingDaysExceptSunday();
        
        // List to store Employee records
        List<Employee__c> employees = new List<Employee__c>();
        
        // Create Employee records from Users
        for(User u : usersToProcess) {
            String emailKey = u.Email == null ? null : u.Email.trim().toLowerCase();
            if (String.isBlank(emailKey) || existingEmployeeEmails.contains(emailKey)) {
                continue;
            }

            Employee__c emp = new Employee__c();
            String firstName = String.isBlank(u.FirstName) ? '' : u.FirstName.trim();
            String lastName = String.isBlank(u.LastName) ? '' : u.LastName.trim();
            String fullName = (firstName + ' ' + lastName).trim();
            emp.Name = String.isBlank(fullName) ? ('Employee ' + String.valueOf(u.Id)) : fullName;
            emp.User__c = u.Id;
            emp.Is_Active__c = true;
            emp.Working_Days__c = workingDays;
            System.debug('Employee Name is :::: '+ emp.Name);
            employees.add(emp);
            existingEmployeeEmails.add(emailKey);
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