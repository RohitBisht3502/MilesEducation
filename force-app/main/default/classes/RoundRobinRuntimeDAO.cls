public without sharing class RoundRobinRuntimeDAO {
    public class Runtime {
        public String key;
        public Id lastAssignedUserId;
        public Datetime lastAssignedAt;
        public Datetime cycleStartedAt;
    }

    public static Runtime getOrCreateLocked(String key) {
        List<Round_Robin_Runtime__c> rows = [
            SELECT Id, Key__c, Last_Assigned_User_Id__c, Last_Assigned_At__c, Cycle_Started_At__c
            FROM Round_Robin_Runtime__c
            WHERE Key__c = :key
            LIMIT 1
            FOR UPDATE
        ];
        Runtime rt = new Runtime();
        rt.key = key;
        if (!rows.isEmpty()) {
            Round_Robin_Runtime__c r = rows[0];
            rt.lastAssignedUserId = (r.Last_Assigned_User_Id__c == null) ? null : (Id)r.Last_Assigned_User_Id__c;
            rt.lastAssignedAt = r.Last_Assigned_At__c;
            rt.cycleStartedAt = r.Cycle_Started_At__c;
        } else {
            rt.cycleStartedAt = System.now();
        }
        return rt;
    }

    public static void upsertLocked(Runtime rt) {
        List<Round_Robin_Runtime__c> existing = [
            SELECT Id
            FROM Round_Robin_Runtime__c
            WHERE Key__c = :rt.key
            LIMIT 1
        ];
        Round_Robin_Runtime__c row;
        if (existing.isEmpty()) {
            row = new Round_Robin_Runtime__c();
            row.Key__c = rt.key;
            row.Name   = rt.key;
        } else {
            row = existing[0];
        }
        row.Last_Assigned_User_Id__c = (rt.lastAssignedUserId == null ? null : String.valueOf(rt.lastAssignedUserId));
        row.Last_Assigned_At__c = rt.lastAssignedAt;
        row.Cycle_Started_At__c = rt.cycleStartedAt;
        if (row.Id == null) insert row; else update row;
    }
}