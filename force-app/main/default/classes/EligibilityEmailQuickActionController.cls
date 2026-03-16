public without sharing class EligibilityEmailQuickActionController {
    private static final String STATUS_REPORT_GENERATED = 'Eligibility Report Generated';

    public class TemplateOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String subject;
        @AuraEnabled public String content;
    }

    public class FileStatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }

    public class EmailInitData {
        @AuraEnabled public String recordType;
        @AuraEnabled public String recordName;
        @AuraEnabled public String candidateName;
        @AuraEnabled public String studentName;
        @AuraEnabled public String uuid;
        @AuraEnabled public String eligibilityCode;
        @AuraEnabled public String eligibilityStatus;
        @AuraEnabled public String gpStatus;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String email;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String gpOwnerName;
        @AuraEnabled public Integer totalFiles;
        @AuraEnabled public List<FileStatusCount> fileStatusCounts;
        @AuraEnabled public List<TemplateOption> templates;
    }

    @AuraEnabled(cacheable=true)
    public static EmailInitData getInitData(Id recordId) {
        EmailInitData res = new EmailInitData();
        res.fileStatusCounts = new List<FileStatusCount>();
        res.templates = new List<TemplateOption>();
        res.totalFiles = 0;

        if (recordId == null) {
            return res;
        }

        Schema.SObjectType sType = recordId.getSObjectType();
        Boolean isCandidate = sType == Lead.SObjectType;
        Boolean isStudent = sType == Account.SObjectType;

        if (!isCandidate && !isStudent) {
            return res;
        }

        EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByRecordId(recordId);
        res.uuid = EligibilityRecordResolver.resolveUuid(ctx);
        res.recordType = isCandidate ? 'Candidate' : 'Student';

        Lead cand;
        if (ctx.candidateId != null) {
            cand = [
                SELECT Id, Name, Email, Owner.Name, GP_User__c, GP_User__r.Name,
                       GP_Lead_Status__c, CPA_Eligibility_Status__c, Credit_score__c, UUID__c,
                       Eligibility_Code__c
                FROM Lead
                WHERE Id = :ctx.candidateId
                LIMIT 1
            ];
            res.candidateName = cand.Name;
        }

        Account stud;
        if (ctx.studentId != null) {
            stud = [
                SELECT Id, Name, Email__c, Owner.Name, GP_User__c, GP_User__r.Name,
                       GP_Lead_Status__c, CPA_Eligibility_Status__c, Credit_score__c, UUID__c,
                       Eligibility_Code__c
                FROM Account
                WHERE Id = :ctx.studentId
                LIMIT 1
            ];
            res.studentName = stud.Name;
        }

        if (isCandidate) {
            res.recordName = cand != null ? cand.Name : null;
            res.email = cand != null ? cand.Email : null;
            res.ownerName = cand != null && cand.Owner != null ? cand.Owner.Name : null;
            res.gpOwnerName = cand != null && cand.GP_User__c != null ? cand.GP_User__r.Name : null;
            res.eligibilityStatus = cand != null ? cand.CPA_Eligibility_Status__c : null;
            res.gpStatus = cand != null ? cand.GP_Lead_Status__c : null;
            res.score = cand != null ? cand.Credit_score__c : null;
            res.eligibilityCode = cand != null ? cand.Eligibility_Code__c : null;
        } else {
            res.recordName = stud != null ? stud.Name : null;
            res.email = stud != null ? stud.Email__c : null;
            res.ownerName = stud != null && stud.Owner != null ? stud.Owner.Name : null;
            res.gpOwnerName = stud != null && stud.GP_User__c != null ? stud.GP_User__r.Name : null;
            res.eligibilityStatus = stud != null ? stud.CPA_Eligibility_Status__c : null;
            res.gpStatus = stud != null ? stud.GP_Lead_Status__c : null;
            res.score = stud != null ? stud.Credit_score__c : null;
            res.eligibilityCode = stud != null ? stud.Eligibility_Code__c : null;
        }

        List<AggregateResult> aggregates = new List<AggregateResult>();
        if (ctx.studentId != null && ctx.candidateId != null) {
            aggregates = [
                SELECT Status__c status, COUNT(Id) cnt
                FROM Eligibility_File__c
                WHERE Student__c = :ctx.studentId OR Candidate__c = :ctx.candidateId
                GROUP BY Status__c
            ];
        } else if (ctx.studentId != null) {
            aggregates = [
                SELECT Status__c status, COUNT(Id) cnt
                FROM Eligibility_File__c
                WHERE Student__c = :ctx.studentId
                GROUP BY Status__c
            ];
        } else if (ctx.candidateId != null) {
            aggregates = [
                SELECT Status__c status, COUNT(Id) cnt
                FROM Eligibility_File__c
                WHERE Candidate__c = :ctx.candidateId
                GROUP BY Status__c
            ];
        }

        Map<String, Integer> counts = new Map<String, Integer>();
        Integer total = 0;
        for (AggregateResult ar : aggregates) {
            String status = (String) ar.get('status');
            Integer count = (Integer) ar.get('cnt');
            if (count == null) count = 0;
            if (String.isBlank(status)) status = 'Submitted';
            counts.put(status, (counts.containsKey(status) ? counts.get(status) : 0) + count);
            total += count;
        }
        res.totalFiles = total;

        List<String> preferredOrder = new List<String>{
            'Verified',
            'Recheck/Reupload',
            'Not Applicable',
            'Not application',
            'Submitted'
        };

        Set<String> used = new Set<String>();
        for (String key : preferredOrder) {
            if (counts.containsKey(key)) {
                FileStatusCount sc = new FileStatusCount();
                sc.status = key;
                sc.count = counts.get(key);
                res.fileStatusCounts.add(sc);
                used.add(key);
            }
        }

        List<String> remaining = new List<String>();
        for (String key : counts.keySet()) {
            if (!used.contains(key)) {
                remaining.add(key);
            }
        }
        remaining.sort();
        for (String key : remaining) {
            FileStatusCount sc = new FileStatusCount();
            sc.status = key;
            sc.count = counts.get(key);
            res.fileStatusCounts.add(sc);
        }

        for (Template_Eligibility__c t : [
            SELECT Id, Name, Content__c, Subject__c
            FROM Template_Eligibility__c
            ORDER BY Name
        ]) {
            TemplateOption opt = new TemplateOption();
            opt.id = t.Id;
            opt.name = t.Name;
            opt.subject = String.isNotBlank(t.Subject__c) ? t.Subject__c : t.Name;
            opt.content = t.Content__c;
            res.templates.add(opt);
        }

        return res;
    }

    @AuraEnabled
    public static void sendEligibilityEmail(Id recordId, Id templateId, String subject, String body) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        if (templateId == null) {
            throw new AuraHandledException('Template is required.');
        }

        Schema.SObjectType sType = recordId.getSObjectType();
        Boolean isCandidate = sType == Lead.SObjectType;
        Boolean isStudent = sType == Account.SObjectType;

        if (!isCandidate && !isStudent) {
            throw new AuraHandledException('Unsupported record type.');
        }

        EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByRecordId(recordId);

        Lead cand;
        if (ctx.candidateId != null) {
            cand = [
                SELECT Id, Name, Email, Owner.Name, GP_User__c, GP_User__r.Name
                FROM Lead
                WHERE Id = :ctx.candidateId
                LIMIT 1
            ];
        }

        Account stud;
        if (ctx.studentId != null) {
            stud = [
                SELECT Id, Name, Email__c, Owner.Name, GP_User__c, GP_User__r.Name
                FROM Account
                WHERE Id = :ctx.studentId
                LIMIT 1
            ];
        }

        String email = isCandidate
            ? (cand != null ? cand.Email : null)
            : (stud != null ? stud.Email__c : null);

        if (String.isBlank(email)) {
            throw new AuraHandledException('Email address is missing on this record.');
        }

        Template_Eligibility__c tpl = [
            SELECT Id, Name, Content__c, Subject__c
            FROM Template_Eligibility__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        String candidateName = (cand != null && String.isNotBlank(cand.Name))
            ? cand.Name
            : (stud != null ? stud.Name : null);

        String ownerName = isCandidate
            ? (cand != null && cand.Owner != null ? cand.Owner.Name : null)
            : (stud != null && stud.Owner != null ? stud.Owner.Name : null);

        String gpOwnerName = isCandidate
            ? (cand != null && cand.GP_User__c != null ? cand.GP_User__r.Name : null)
            : (stud != null && stud.GP_User__c != null ? stud.GP_User__r.Name : null);

        Boolean subjectFromTemplate = String.isBlank(subject);
        Boolean bodyFromTemplate = String.isBlank(body);

        String resolvedSubject = subjectFromTemplate
            ? (String.isNotBlank(tpl.Subject__c) ? tpl.Subject__c : tpl.Name)
            : subject;
        String resolvedBody = bodyFromTemplate ? tpl.Content__c : body;

        if (String.isBlank(resolvedSubject)) {
            resolvedSubject = 'Eligibility Report';
        }
        if (subjectFromTemplate) {
            resolvedSubject = applyTokenReplacementsPlain(resolvedSubject, candidateName, ownerName, gpOwnerName);
        }
        if (bodyFromTemplate) {
            resolvedBody = applyTokenReplacements(resolvedBody, candidateName, ownerName, gpOwnerName);
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ email });
        mail.setSubject(resolvedSubject);
        if (!String.isBlank(resolvedBody)) {
            mail.setHtmlBody(resolvedBody);
        } else {
            mail.setPlainTextBody(' ');
        }
        mail.setSaveAsActivity(false);

        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new Messaging.SingleEmailMessage[]{ mail },
            false
        );

        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            String message = 'Unable to send email.';
            if (results != null && !results.isEmpty()) {
                Messaging.SendEmailError[] errors = results[0].getErrors();
                if (errors != null && !errors.isEmpty()) {
                    message = errors[0].getMessage();
                }
            }
            throw new AuraHandledException(message);
        }

        if (isCandidate && ctx.candidateId != null) {
            String resolved = resolvePicklistValue(Lead.SObjectType, 'GP_Lead_Status__c', STATUS_REPORT_GENERATED);
            update new Lead(Id = ctx.candidateId, GP_Lead_Status__c = resolved);
        } else if (isStudent && ctx.studentId != null) {
            String resolved = resolvePicklistValue(Account.SObjectType, 'GP_Lead_Status__c', STATUS_REPORT_GENERATED);
            update new Account(Id = ctx.studentId, GP_Lead_Status__c = resolved);
        }
    }

    private static String applyTokenReplacements(
        String input,
        String candidateName,
        String ownerName,
        String gpOwnerName
    ) {
        if (String.isBlank(input)) return input;
        String safeCandidate = safeToken(candidateName);
        String safeOwner = safeToken(ownerName);
        String safeGp = safeToken(gpOwnerName);

        String out = input;
        out = out.replace('XXX', safeCandidate);
        out = out.replace('YYY', safeOwner);
        out = out.replace('ZZZ', safeGp);
        return out;
    }

    private static String applyTokenReplacementsPlain(
        String input,
        String candidateName,
        String ownerName,
        String gpOwnerName
    ) {
        if (String.isBlank(input)) return input;
        String safeCandidate = candidateName != null ? candidateName : '';
        String safeOwner = ownerName != null ? ownerName : '';
        String safeGp = gpOwnerName != null ? gpOwnerName : '';

        String out = input;
        out = out.replace('XXX', safeCandidate);
        out = out.replace('YYY', safeOwner);
        out = out.replace('ZZZ', safeGp);
        return out;
    }

    private static String safeToken(String value) {
        if (String.isBlank(value)) return '';
        String out = value;
        out = out.replace('&', '&amp;');
        out = out.replace('<', '&lt;');
        out = out.replace('>', '&gt;');
        out = out.replace('"', '&quot;');
        out = out.replace('\'', '&#39;');
        return out;
    }

    private static String resolvePicklistValue(
        Schema.SObjectType sobjectType,
        String fieldApi,
        String desiredValue
    ) {
        if (sobjectType == null || String.isBlank(fieldApi) || String.isBlank(desiredValue)) {
            return desiredValue;
        }
        Schema.DescribeSObjectResult d = sobjectType.getDescribe();
        Map<String, Schema.SObjectField> fields = d != null ? d.fields.getMap() : null;
        if (fields == null || !fields.containsKey(fieldApi)) {
            return desiredValue;
        }
        Schema.DescribeFieldResult fr = fields.get(fieldApi).getDescribe();
        if (fr == null || fr.getType() != Schema.DisplayType.Picklist) {
            return desiredValue;
        }
        for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
            if (pe != null && pe.getValue() == desiredValue) {
                return desiredValue;
            }
        }
        for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
            if (pe != null && pe.getValue() != null && pe.getValue().equalsIgnoreCase(desiredValue)) {
                return pe.getValue();
            }
        }
        return desiredValue;
    }
}