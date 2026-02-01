public class LeadTriggerConversionClass {
    public static void convertCandidateAndCreateCourseOnM7(
        List<Lead__c> newLeads,
        Map<Id, Lead__c> oldMap
    ) {
        System.debug('=== LeadTriggerConversionClass.convertCandidateAndCreateCourseOnM7 START ===');
        System.debug(
            'Incoming newLeads size=' + (newLeads == null ? 0 : newLeads.size()) +
            ', oldMap null?=' + (oldMap == null)
        );
        
        Set<Id> leadCIdsToProcess = new Set<Id>();
        Set<Id> candidateLeadIds = new Set<Id>();
        
        for (Lead__c n : newLeads) {
            Lead__c o = oldMap != null ? oldMap.get(n.Id) : null;
            
            if (n.Candidate__c == null) {
                System.debug('Skip Lead__c Id=' + n.Id + ' because Candidate__c is NULL');
                continue;
            }
            
            Boolean movedToM7 = (n.Stage__c == 'M7') && (o == null || o.Stage__c != 'M7');
            
            if (!movedToM7) {
                System.debug(
                    'Skip Lead__c Id=' + n.Id + ' Candidate__c=' + n.Candidate__c +
                    ' because movedToM7=false ' +
                    '(newStage=' + n.Stage__c + ', oldStage=' + (o == null ? 'null' : o.Stage__c) + ')'
                );
                continue;
            }
            
            leadCIdsToProcess.add(n.Id);
            candidateLeadIds.add(n.Candidate__c);
            System.debug('ToProcess Lead__c Id=' + n.Id + ' Candidate__c=' + n.Candidate__c + ' (moved to M7)');
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
            SELECT Id, Name, IsConverted, ConvertedAccountId
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
        Set<Id> studentsHavingCourseEnrolled = new Set<Id>();
        
        List<Course_Enrolled__c> existingCE = [
            SELECT Id, Student__c
            FROM Course_Enrolled__c
            WHERE Student__c IN :studentAccountIds
        ];
        
        for (Course_Enrolled__c ce : existingCE) {
            if (ce.Student__c != null) {
                studentsHavingCourseEnrolled.add(ce.Student__c);
            }
        }
        
        List<Lead__c> leadCToUpdate = new List<Lead__c>();
        List<Course_Enrolled__c> ceToInsert = new List<Course_Enrolled__c>();
        
        for (Lead__c n : newLeads) {
            if (!leadCIdsToProcess.contains(n.Id)) {
                continue;
            }
            
            Id accId = candidateToAccount.get(n.Candidate__c);
            if (accId == null) {
                continue;
            }
            
            if (n.Student__c != accId) {
                leadCToUpdate.add(new Lead__c(Id = n.Id, Student__c = accId));
            }
            
            if (!studentsHavingCourseEnrolled.contains(accId)) {
                Course_Enrolled__c ce = new Course_Enrolled__c();
                ce.Student__c = accId;
                ceToInsert.add(ce);
                studentsHavingCourseEnrolled.add(accId);
            }
        }
        
        if (!ceToInsert.isEmpty()) {
            insert ceToInsert;
        }
        
        if (!leadCToUpdate.isEmpty()) {
            update leadCToUpdate;
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
}