/*
    Author       : Rohit Singh Bisht
*/
public without sharing class ActivityLogContextService {

    public static void applyContext(List<Activity_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }

        Map<String, Schema.SObjectField> activityFieldMap =
            Activity_Log__c.SObjectType.getDescribe().fields.getMap();

        Set<Id> leadIds = new Set<Id>();
        Set<Id> candidateIds = new Set<Id>();
        Set<Id> studentIds = new Set<Id>();

        for (Activity_Log__c logRec : logs) {
            if (logRec == null) {
                continue;
            }
            if (logRec.Lead__c != null) {
                leadIds.add(logRec.Lead__c);
            }
            if (logRec.Candidate__c != null) {
                candidateIds.add(logRec.Candidate__c);
            }
            if (logRec.Student__c != null) {
                studentIds.add(logRec.Student__c);
            }
        }

        Map<Id, Lead__c> leadMap = leadIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([SELECT Id, OwnerId, Stage__c, Candidate__c, Student__c, GP_SPOC__c, Candidate__r.Highest_Level__c, Candidate__r.GP_User__c, Student__r.Highest_Level__c, Student__r.GP_User__c FROM Lead__c WHERE Id IN :leadIds]);

        Map<Id, Lead> candidateMap = candidateIds.isEmpty()
            ? new Map<Id, Lead>()
            : new Map<Id, Lead>([SELECT Id, OwnerId, GP_User__c, Highest_Level__c FROM Lead WHERE Id IN :candidateIds]);

        Map<Id, Account> studentMap = studentIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([SELECT Id, OwnerId, GP_User__c, Highest_Level__c FROM Account WHERE Id IN :studentIds]);

        Map<Id, Lead__c> latestLeadByCandidate = new Map<Id, Lead__c>();
        if (!candidateIds.isEmpty()) {
            for (Lead__c leadRec : [SELECT Id, Candidate__c, Stage__c FROM Lead__c WHERE Candidate__c IN :candidateIds ORDER BY CreatedDate DESC]) {
                if (!latestLeadByCandidate.containsKey(leadRec.Candidate__c)) {
                    latestLeadByCandidate.put(leadRec.Candidate__c, leadRec);
                }
            }
        }

        Map<Id, Lead__c> latestLeadByStudent = new Map<Id, Lead__c>();
        if (!studentIds.isEmpty()) {
            for (Lead__c leadRec : [SELECT Id, Student__c, Stage__c FROM Lead__c WHERE Student__c IN :studentIds ORDER BY CreatedDate DESC]) {
                if (!latestLeadByStudent.containsKey(leadRec.Student__c)) {
                    latestLeadByStudent.put(leadRec.Student__c, leadRec);
                }
            }
        }

        Set<Id> userIds = new Set<Id>();
        Map<Integer, Id> ownerByIndex = new Map<Integer, Id>();
        Map<Integer, Id> gpUserByIndex = new Map<Integer, Id>();
        Map<Integer, String> currentLevelByIndex = new Map<Integer, String>();
        Map<Integer, String> highestLevelByIndex = new Map<Integer, String>();

        Integer rowKey = 0;
        for (Activity_Log__c logRec : logs) {
            rowKey++;
            Id ownerId;
            Id gpUserId;
            String currentLevel;
            String highestLevel;

            if (logRec.Lead__c != null && leadMap.containsKey(logRec.Lead__c)) {
                Lead__c leadRec = leadMap.get(logRec.Lead__c);
                ownerId = leadRec.OwnerId;
                currentLevel = leadRec.Stage__c;
                gpUserId = leadRec.GP_SPOC__c != null
                    ? leadRec.GP_SPOC__c
                    : (leadRec.Candidate__c != null ? leadRec.Candidate__r.GP_User__c : leadRec.Student__r.GP_User__c);
                highestLevel = leadRec.Candidate__c != null
                    ? leadRec.Candidate__r.Highest_Level__c
                    : leadRec.Student__r.Highest_Level__c;
            } else if (logRec.Candidate__c != null && candidateMap.containsKey(logRec.Candidate__c)) {
                Lead cand = candidateMap.get(logRec.Candidate__c);
                ownerId = cand.OwnerId;
                gpUserId = cand.GP_User__c;
                highestLevel = cand.Highest_Level__c;
                Lead__c latestLead = latestLeadByCandidate.get(logRec.Candidate__c);
                currentLevel = latestLead != null ? latestLead.Stage__c : null;
            } else if (logRec.Student__c != null && studentMap.containsKey(logRec.Student__c)) {
                Account stu = studentMap.get(logRec.Student__c);
                ownerId = stu.OwnerId;
                gpUserId = stu.GP_User__c;
                highestLevel = stu.Highest_Level__c;
                Lead__c latestLead = latestLeadByStudent.get(logRec.Student__c);
                currentLevel = latestLead != null ? latestLead.Stage__c : null;
            }

            ownerByIndex.put(rowKey, ownerId);
            gpUserByIndex.put(rowKey, gpUserId);
            currentLevelByIndex.put(rowKey, currentLevel);
            highestLevelByIndex.put(rowKey, highestLevel);

            if (ownerId != null) {
                userIds.add(ownerId);
            }
            if (gpUserId != null) {
                userIds.add(gpUserId);
            }
        }

        Map<Id, User> userMap = userIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, ManagerId, Manager.Name FROM User WHERE Id IN :userIds]);

        rowKey = 0;
        for (Activity_Log__c logRec : logs) {
            rowKey++;
            Id ownerId = ownerByIndex.get(rowKey);
            Id gpUserId = gpUserByIndex.get(rowKey);

            putIfFieldExists(activityFieldMap, logRec, 'Current_Owner__c', ownerId);
            putIfFieldExists(activityFieldMap, logRec, 'Current_GP_User__c', gpUserId);
            putIfFieldExists(activityFieldMap, logRec, 'Current_Highest_Level__c', highestLevelByIndex.get(rowKey));
            putIfFieldExists(activityFieldMap, logRec, 'Current_Level__c', currentLevelByIndex.get(rowKey));

            User ownerUser = ownerId != null ? userMap.get(ownerId) : null;
            User gpUser = gpUserId != null ? userMap.get(gpUserId) : null;

            putIfFieldExists(activityFieldMap, logRec, 'Current_GM__c',
                ownerUser != null && ownerUser.ManagerId != null ? ownerUser.Manager.Name : null);
            putIfFieldExists(activityFieldMap, logRec, 'Current_GP_User_GM__c',
                gpUser != null && gpUser.ManagerId != null ? gpUser.Manager.Name : null);
        }
    }

    private static void putIfFieldExists(
        Map<String, Schema.SObjectField> fieldMap,
        Activity_Log__c logRec,
        String fieldApiName,
        Object value
    ) {
        if (fieldMap.containsKey(fieldApiName)) {
            logRec.put(fieldApiName, value);
        }
    }
}
