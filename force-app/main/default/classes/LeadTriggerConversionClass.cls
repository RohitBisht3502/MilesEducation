public class LeadTriggerConversionClass {
    public static void convertCandidateOnFullPayment( List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        System.debug('=== LeadTriggerConversionClass.convertCandidateOnFullPayment START ===');
        System.debug(
            'Incoming newLeads size=' + (newLeads == null ? 0 : newLeads.size()) +
            ', oldMap null?=' + (oldMap == null)
        );
        
        Set<Id> leadCIdsToProcess = new Set<Id>();
        Set<Id> candidateLeadIds = new Set<Id>();
        Set<String> allowedRecordTypes = new Set<String>{ 'CPA', 'CMA', 'USP Pathway' };
        
        for (Lead__c n : newLeads) {
            Lead__c o = oldMap != null ? oldMap.get(n.Id) : null;
            
            if (n.Candidate__c == null) {
                System.debug('Skip Lead__c Id=' + n.Id + ' because Candidate__c is NULL');
                continue;
            }

            String rtName = getLeadRecordTypeName(n.RecordTypeId);
            if (String.isBlank(rtName) || !allowedRecordTypes.contains(rtName)) {
                System.debug('Skip Lead__c Id=' + n.Id + ' because RecordType not allowed: ' + rtName);
                continue;
            }
            
            Boolean fullPaymentReceived =
                (n.Payment_Received__c == 'Fully Received') &&
                (o == null || o.Payment_Received__c != 'Fully Received');
            
            if (!fullPaymentReceived) {
                System.debug(
                    'Skip Lead__c Id=' + n.Id + ' Candidate__c=' + n.Candidate__c +
                    ' because fullPaymentReceived=false ' +
                    '(newPayment=' + n.Payment_Received__c + ', oldPayment=' + (o == null ? 'null' : o.Payment_Received__c) + ')'
                );
                continue;
            }
            
            leadCIdsToProcess.add(n.Id);
            candidateLeadIds.add(n.Candidate__c);
            System.debug('ToProcess Lead__c Id=' + n.Id + ' Candidate__c=' + n.Candidate__c + ' (full payment received)');
        }
        
        System.debug(
            'leadCIdsToProcess size=' + leadCIdsToProcess.size() +
            ', candidateLeadIds size=' + candidateLeadIds.size()
        );
        
        if (leadCIdsToProcess.isEmpty() || candidateLeadIds.isEmpty()) {
            System.debug('EXIT: Nothing to process.');
            return;
        }
        
        Map<Id, Lead> candMap = new Map<Id, Lead>([
            SELECT Id, Name, IsConverted, ConvertedAccountId, GP_User__c, OwnerId
            FROM Lead
            WHERE Id IN :candidateLeadIds
        ]);
        System.debug('candMap size=' + candMap.size());
        
        String convertedStatus = getConvertedLeadStatus();
        System.debug('Converted Lead Status resolved: ' + convertedStatus);
        
        List<Database.LeadConvert> converts = new List<Database.LeadConvert>();
        
        for (Lead cand : candMap.values()) {
            if (cand.IsConverted) {
                System.debug(
                    'Candidate Lead already converted: candId=' + cand.Id +
                    ', ConvertedAccountId=' + cand.ConvertedAccountId
                );
                continue;
            }
            
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(cand.Id);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(true);
            
            Account acc = new Account(Name = cand.Name);
            insert acc;
            lc.setAccountId(acc.Id);
            
            System.debug(
                'Prepared convert request for candId=' + cand.Id +
                ' with AccountId=' + acc.Id + ' (Name=' + cand.Name + ')'
            );
            converts.add(lc);
        }
        
        Map<Id, Id> candidateToAccount = new Map<Id, Id>();
        
        if (!converts.isEmpty()) {
            System.debug('Calling Database.convertLead for converts size=' + converts.size());
            List<Database.LeadConvertResult> results = Database.convertLead(converts, false);
            System.debug('convertLead results size=' + (results == null ? 0 : results.size()));
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.LeadConvertResult r = results[i];
                Id candId = converts[i].getLeadId();
                
                if (!r.isSuccess()) {
                    System.debug('convertLead FAILED for candId=' + candId);
                    if (r.getErrors() != null) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug('Error => ' + e.getStatusCode() + ' : ' + e.getMessage());
                        }
                    }
                    continue;
                }
                
                candidateToAccount.put(candId, r.getAccountId());
                System.debug('convertLead SUCCESS candId=' + candId + ' => accountId=' + r.getAccountId());
            }
        }
        
        for (Lead cand : candMap.values()) {
            if (cand.IsConverted && cand.ConvertedAccountId != null) {
                candidateToAccount.put(cand.Id, cand.ConvertedAccountId);
                System.debug(
                    'Candidate already converted mapped: candId=' + cand.Id +
                    ' => accountId=' + cand.ConvertedAccountId
                );
            }
        }
        
        if (candidateToAccount.isEmpty()) {
            System.debug('EXIT: candidateToAccount empty after conversion.');
            return;
        }
        
        Set<Id> studentAccountIds = new Set<Id>(candidateToAccount.values());
        Set<String> studentCourseKeysHavingCourseEnrolled = new Set<String>();

        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, OwnerId
            FROM Account
            WHERE Id IN :studentAccountIds
        ]);
        
        List<Course_Enrolled__c> existingCE = [
            SELECT Id, Student__c, Course__c
            FROM Course_Enrolled__c
            WHERE Student__c IN :studentAccountIds
        ];
        
        for (Course_Enrolled__c ce : existingCE) {
            if (ce.Student__c != null) {
                studentCourseKeysHavingCourseEnrolled.add(
                    buildStudentCourseKey(ce.Student__c, ce.Course__c)
                );
            }
        }
        
        List<Lead__c> leadCToUpdate = new List<Lead__c>();
        List<Course_Enrolled__c> ceToInsert = new List<Course_Enrolled__c>();
        Map<Id, Id> leadToAccount = new Map<Id, Id>();
        Map<String, Id> ceRecordTypeByName = getCourseRecordTypeIdsByName();
        
        for (Lead__c n : newLeads) {
            if (!leadCIdsToProcess.contains(n.Id)) {
                continue;
            }
            
            Id accId = candidateToAccount.get(n.Candidate__c);
            if (accId == null) {
                continue;
            }
            Account studentAcc = accMap.get(accId);

            String rtName = getLeadRecordTypeName(n.RecordTypeId);
            if (String.isBlank(rtName) || !allowedRecordTypes.contains(rtName)) {
                continue;
            }

            String courseValue = resolveCourseForLead(n, rtName);
            
            if (n.Student__c != accId) {
                leadCToUpdate.add(new Lead__c(Id = n.Id, Student__c = accId));
            }
            leadToAccount.put(n.Id, accId);
            
            String studentCourseKey = buildStudentCourseKey(accId, courseValue);
            if (!studentCourseKeysHavingCourseEnrolled.contains(studentCourseKey)) {
                Course_Enrolled__c ce = new Course_Enrolled__c();
                ce.Student__c = accId;
                if (studentAcc != null && studentAcc.OwnerId != null) {
                    ce.OwnerId = studentAcc.OwnerId;
                }
                ce.CC_Spoc__c = n.OwnerId;
                ce.Source__c = n.Source__c;
                ce.Phone__c = n.Phone__c;
                ce.Course__c = courseValue;
                ce.City__c = n.City__c;
                ce.Course_Bucket__c = n.Course_Bucket__c;
                Id ceRtId = ceRecordTypeByName.get(rtName);
                if (ceRtId != null) {
                    ce.RecordTypeId = ceRtId;
                }
                Lead candidateLead = candMap.get(n.Candidate__c);
                if (candidateLead != null) {
                    ce.GP_SPOC__c = candidateLead.GP_User__c != null
                        ? candidateLead.GP_User__c
                        : candidateLead.OwnerId;
                }
                ceToInsert.add(ce);
                studentCourseKeysHavingCourseEnrolled.add(studentCourseKey);
            }
        }
        
        if (!ceToInsert.isEmpty()) {
            insert ceToInsert;
        }
        
        if (!leadCToUpdate.isEmpty()) {
            update leadCToUpdate;
        }

        if (!leadToAccount.isEmpty()) {
            List<Purchase_Order__c> poToUpdate = new List<Purchase_Order__c>();
            for (Purchase_Order__c po : [
                SELECT Id, Lead__c, Student__c
                FROM Purchase_Order__c
                WHERE Lead__c IN :leadToAccount.keySet()
            ]) {
                Id accId = leadToAccount.get(po.Lead__c);
                if (accId != null && po.Student__c != accId) {
                    po.Student__c = accId;
                    poToUpdate.add(po);
                }
            }
            if (!poToUpdate.isEmpty()) {
                update poToUpdate;
            }
        }
        
        syncAccountAddressesFromCandidate(candidateToAccount);
        transferRecordsOnCandidateConversion(candidateToAccount);
        
        System.debug('=== END ===');
    }
    
    private static void transferRecordsOnCandidateConversion(Map<Id, Id> candidateToAccount) {
        Set<Id> candidateIds = candidateToAccount.keySet();
        
        if (candidateIds.isEmpty()) {
            return;
        }
        
        List<Enquiry__c> toUpdate = new List<Enquiry__c>();
        List<Enquiry__c> enqs = [
            SELECT Id, Candidate__c, Student__c
            FROM Enquiry__c
            WHERE Candidate__c IN :candidateIds
        ];
        
        for (Enquiry__c e : enqs) {
            Id accId = candidateToAccount.get(e.Candidate__c);
            if (accId != null && e.Student__c != accId) {
                e.Student__c = accId;
                toUpdate.add(e);
            }
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
    
    private static void syncAccountAddressesFromCandidate(Map<Id, Id> candidateToAccount) {
        if (candidateToAccount.isEmpty()) {
            return;
        }
        
        Map<Id, Lead> candMap = new Map<Id, Lead>([
            SELECT Id, Street, City, State, PostalCode, Country
            FROM Lead
            WHERE Id IN :candidateToAccount.keySet()
        ]);
        
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
            FROM Account
            WHERE Id IN :candidateToAccount.values()
        ]);
        
        List<Account> toUpdate = new List<Account>();
        
        for (Id candId : candidateToAccount.keySet()) {
            Account acc = accMap.get(candidateToAccount.get(candId));
            Lead l = candMap.get(candId);
            
            if (acc == null || l == null) {
                continue;
            }
            
            if (String.isBlank(acc.BillingStreet)) {
                acc.BillingStreet = l.Street;
            }
            
            toUpdate.add(acc);
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
    
    private static String getConvertedLeadStatus() {
        LeadStatus ls = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];
        return ls.MasterLabel;
    }

    private static String buildStudentCourseKey(Id studentId, String course) {
        return String.valueOf(studentId) + '|' + String.valueOf(course);
    }

    private static String getLeadRecordTypeName(Id recordTypeId) {
        if (recordTypeId == null) return null;
        Schema.RecordTypeInfo rti = Schema.SObjectType.Lead__c.getRecordTypeInfosById().get(recordTypeId);
        return rti != null ? rti.getName() : null;
    }

    private static Map<String, Id> getCourseRecordTypeIdsByName() {
        Map<String, Id> mapRt = new Map<String, Id>();
        Map<String, Schema.RecordTypeInfo> byName = Schema.SObjectType.Course_Enrolled__c.getRecordTypeInfosByName();
        for (String key : byName.keySet()) {
            Schema.RecordTypeInfo rti = byName.get(key);
            if (rti != null && rti.isAvailable()) {
                mapRt.put(key, rti.getRecordTypeId());
            }
        }
        return mapRt;
    }

    private static String resolveCourseForLead(Lead__c leadRec, String recordTypeName) {
        if (leadRec != null && !String.isBlank(leadRec.Course__c)) {
            return leadRec.Course__c;
        }
        return recordTypeName;
    }
}