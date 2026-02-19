public class LeadTriggerConversionClass {
    public static void convertCandidateOnFullPayment( List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        System.debug('=== LeadTriggerConversionClass.convertCandidateOnFullPayment START ===');
        System.debug(
            'Incoming newLeads size=' + (newLeads == null ? 0 : newLeads.size()) +
            ', oldMap null?=' + (oldMap == null)
        );
        
        Set<Id> leadCIdsToProcess = new Set<Id>();
        Set<Id> candidateLeadIds = new Set<Id>();
        Set<String> allowedRecordTypes = new Set<String>{ 'CPA', 'CMA', 'US Pathway' };
        
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
            SELECT Id, Name, IsConverted, ConvertedAccountId, GP_User__c, OwnerId,
                   CPA_Level__c, CMA_Level__c, USP_Level__c, CAIRA_Level__c, Highest_Level__c
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
            
            Account acc = new Account(
                Name = cand.Name,
                CPA_Level__c = cand.CPA_Level__c,
                CMA_Level__c = cand.CMA_Level__c,
                USP_Level__c = cand.USP_Level__c,
                CAIRA_Level__c = cand.CAIRA_Level__c,
                Highest_Level__c = cand.Highest_Level__c
            );
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

        List<Account> accLevelUpdates = new List<Account>();
        for (Id candId : candidateToAccount.keySet()) {
            Lead cand = candMap.get(candId);
            Id accId = candidateToAccount.get(candId);
            if (cand == null || accId == null) continue;
            accLevelUpdates.add(new Account(
                Id = accId,
                CPA_Level__c = cand.CPA_Level__c,
                CMA_Level__c = cand.CMA_Level__c,
                USP_Level__c = cand.USP_Level__c,
                CAIRA_Level__c = cand.CAIRA_Level__c,
                Highest_Level__c = cand.Highest_Level__c
            ));
        }
        if (!accLevelUpdates.isEmpty()) {
            update accLevelUpdates;
        }
        
        List<Lead__c> leadCToUpdate = new List<Lead__c>();
        Map<Id, Id> leadToAccount = new Map<Id, Id>();
        
        for (Lead__c n : newLeads) {
            if (!leadCIdsToProcess.contains(n.Id)) {
                continue;
            }
            
            Id accId = candidateToAccount.get(n.Candidate__c);
            if (accId == null) {
                continue;
            }

            String rtName = getLeadRecordTypeName(n.RecordTypeId);
            if (String.isBlank(rtName) || !allowedRecordTypes.contains(rtName)) {
                continue;
            }

            String stageToSet = (rtName == 'US Pathway') ? 'U7+' : 'M7+';
            Boolean needsStudentUpdate = (n.Student__c != accId);
            Boolean needsStageUpdate = (n.Stage__c != stageToSet);

            if (needsStudentUpdate || needsStageUpdate) {
                Lead__c upd = new Lead__c(Id = n.Id);
                if (needsStudentUpdate) upd.Student__c = accId;
                if (needsStageUpdate) upd.Stage__c = stageToSet;
                leadCToUpdate.add(upd);
            }
            leadToAccount.put(n.Id, accId);
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

    private static String getLeadRecordTypeName(Id recordTypeId) {
        if (recordTypeId == null) return null;
        Schema.RecordTypeInfo rti = Schema.SObjectType.Lead__c.getRecordTypeInfosById().get(recordTypeId);
        return rti != null ? rti.getName() : null;
    }
}