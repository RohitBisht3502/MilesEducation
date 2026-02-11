/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RoundRobinConfigProvider {

    public class Config {
        public String objectApiName;
        public String typeValue;

        public String phoneField;
        public String sourceField;
        public String cityField;
        public String courseField;

        public String assignToField;
        public String stickyUserField;

        public Boolean enableSticky;
        public Boolean ignoreSource;
        public Boolean ignoreCourseBucket;
    }

    public static Config getConfig(String objectApiName, String typeValue) {
        if (String.isBlank(objectApiName)) return null;

        String normType = String.isBlank(typeValue) ? 'CC - Pre Enrollment' : typeValue.trim();

        List<Round_Robin_Config__mdt> rows = [
            SELECT Object_Api_Name__c, Type__c, Phone_Field__c, Source_Field__c, City_Field__c, Course_Field__c,
                   Assign_To_Field__c, Sticky_User_Field__c, Enable_Sticky__c, Ignore_Source__c, Ignore_Course_Bucket__c
            FROM Round_Robin_Config__mdt
            WHERE Object_Api_Name__c = :objectApiName AND Type__c = :normType LIMIT 1 ];

        if (rows.isEmpty()) return null;

        Round_Robin_Config__mdt m = rows[0];
        Config c = new Config();
        c.objectApiName    = m.Object_Api_Name__c;
        c.typeValue        = m.Type__c;

        c.phoneField       = m.Phone_Field__c;
        c.sourceField      = m.Source_Field__c;
        c.cityField        = m.City_Field__c;
        c.courseField      = m.Course_Field__c;

        c.assignToField    = String.isBlank(m.Assign_To_Field__c) ? 'OwnerId' : m.Assign_To_Field__c;
        c.stickyUserField  = String.isBlank(m.Sticky_User_Field__c) ? c.assignToField : m.Sticky_User_Field__c;

        c.enableSticky     = m.Enable_Sticky__c;
        c.ignoreSource     = m.Ignore_Source__c;
        c.ignoreCourseBucket = m.Ignore_Course_Bucket__c;
        // Only CC - Pre Enrollment should use sources; all other types are city-wise.
        if (!String.isBlank(c.typeValue) && c.typeValue.equalsIgnoreCase('CC - Pre Enrollment')) {
            c.ignoreSource = false;
        } else if (!String.isBlank(c.typeValue)) {
            c.ignoreSource = true;
            c.ignoreCourseBucket = true;
        }

        return c;
    }
}
