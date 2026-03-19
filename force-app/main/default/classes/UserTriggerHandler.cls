public class UserTriggerHandler {
    public static void createEmployeeAndAttendance(List<User> newUsers) {
        
        // Get all working days except Sunday
        String workingDays = getWorkingDaysExceptSunday();
        
        // List to store Employee records
        List<Employee__c> employees = new List<Employee__c>();
        
        // Create Employee records from Users
        for(User u : newUsers) {
            Employee__c emp = new Employee__c();
            emp.Name = u.FirstName + ' ' + u.LastName;
            emp.User__c = u.Id;
            emp.Is_Active__c = true;
            emp.Working_Days__c = workingDays;
            System.debug('Employee Name is :::: '+ emp.Name);
            employees.add(emp);
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