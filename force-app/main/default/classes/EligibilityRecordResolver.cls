// Utility to resolve Candidate (Lead) and Student (Account) by UUID or record Id.
public without sharing class EligibilityRecordResolver {

    public class Context {
        public Id candidateId;
        public Id studentId;
        public String uuid;
        public Lead candidate;
        public Account student;
    }

    public static Context resolveByKey(String key) {
        Context ctx = new Context();
        ctx.uuid = key;
        if (String.isBlank(key)) {
            return ctx;
        }

        Id parsedId = null;
        try {
            parsedId = key;
        } catch (Exception e) {
            parsedId = null;
        }

        // Student first (as per requirements)
        Account student = null;
        List<Account> students = [
            SELECT Id, OwnerId, UUID__c, GP_User__c
            FROM Account
            WHERE UUID__c = :key
            LIMIT 1
        ];
        if (!students.isEmpty()) {
            student = students[0];
        } else if (parsedId != null) {
            students = [
                SELECT Id, OwnerId, UUID__c, GP_User__c
                FROM Account
                WHERE Id = :parsedId
                LIMIT 1
            ];
            if (!students.isEmpty()) {
                student = students[0];
            }
        }

        Lead candidate = null;
        List<Lead> leads = [
            SELECT Id, OwnerId, GP_User__c, UUID__c
            FROM Lead
            WHERE UUID__c = :key
            LIMIT 1
        ];
        if (!leads.isEmpty()) {
            candidate = leads[0];
        } else if (parsedId != null) {
            leads = [
                SELECT Id, OwnerId, GP_User__c, UUID__c
                FROM Lead
                WHERE Id = :parsedId
                LIMIT 1
            ];
            if (!leads.isEmpty()) {
                candidate = leads[0];
            }
        }

        ctx.student = student;
        ctx.studentId = (student != null) ? student.Id : null;
        ctx.candidate = candidate;
        ctx.candidateId = (candidate != null) ? candidate.Id : null;

        if (student != null && String.isNotBlank(student.UUID__c)) {
            ctx.uuid = student.UUID__c;
        } else if (candidate != null && String.isNotBlank(candidate.UUID__c)) {
            ctx.uuid = candidate.UUID__c;
        }

        return ctx;
    }

    public static Context resolveByRecordId(Id recordId) {
        Context ctx = new Context();
        if (recordId == null) {
            return ctx;
        }

        Schema.SObjectType sobjectType = recordId.getSObjectType();
        if (sobjectType == Lead.SObjectType) {
            List<Lead> leads = [
                SELECT Id, OwnerId, GP_User__c, UUID__c
                FROM Lead
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (!leads.isEmpty()) {
                Lead l = leads[0];
                ctx.candidate = l;
                ctx.candidateId = l.Id;
                ctx.uuid = l.UUID__c;
            }
        } else if (sobjectType == Account.SObjectType) {
            List<Account> accounts = [
                SELECT Id, OwnerId, GP_User__c, UUID__c
                FROM Account
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                Account a = accounts[0];
                ctx.student = a;
                ctx.studentId = a.Id;
                ctx.uuid = a.UUID__c;
            }
        }

        if (String.isNotBlank(ctx.uuid)) {
            Context byUuid = resolveByKey(ctx.uuid);
            if (byUuid.candidateId != null) {
                ctx.candidateId = byUuid.candidateId;
                ctx.candidate = byUuid.candidate;
            }
            if (byUuid.studentId != null) {
                ctx.studentId = byUuid.studentId;
                ctx.student = byUuid.student;
            }
            if (String.isNotBlank(byUuid.uuid)) {
                ctx.uuid = byUuid.uuid;
            }
        }

        return ctx;
    }

    public static String resolveUuid(Context ctx) {
        if (ctx == null) return null;
        if (ctx.student != null && String.isNotBlank(ctx.student.UUID__c)) {
            return ctx.student.UUID__c;
        }
        if (ctx.candidate != null && String.isNotBlank(ctx.candidate.UUID__c)) {
            return ctx.candidate.UUID__c;
        }
        return ctx.uuid;
    }
}