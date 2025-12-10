/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RoundRobinAssigner {
    public static void assignLeadsWithStickyAndRoundRobin(List<Lead__c> leads, String type) {
        if (leads == null || leads.isEmpty()) return;

        String normType = String.isBlank(type) ? 'Round Robin' : type.trim();
        Boolean isEligibility = normType != null && normType.equalsIgnoreCase('Eligibility Criteria');

        Set<String> phones  = new Set<String>();
        Set<String> sources = new Set<String>();

        for (Lead__c l : leads) {
            if (!String.isBlank(l.Phone__c)) phones.add(l.Phone__c.trim());
            if (!String.isBlank(l.Source_Bucket__c)) sources.add(l.Source_Bucket__c.trim());
        }

        Map<String, Id> phoneSourceToUser = new Map<String, Id>();
        Datetime cutoff = System.now().addSeconds(-30);

        if (!phones.isEmpty() && !sources.isEmpty()) {
            List<Lead__c> existingLeads = [
                SELECT Id, OwnerId, GP_User__c, Phone__c, Source_Bucket__c FROM Lead__c WHERE Phone__c IN :phones AND Source_Bucket__c IN :sources AND CreatedDate <= :cutoff ];

            for (Lead__c ex : existingLeads) {
                if (String.isBlank(ex.Phone__c) || String.isBlank(ex.Source_Bucket__c)) continue;
                String key = ex.Phone__c.trim() + '|' + ex.Source_Bucket__c.trim();
                if (!phoneSourceToUser.containsKey(key)) {
                    Id userId = isEligibility ? ex.GP_User__c : ex.OwnerId;
                    if (userId != null) phoneSourceToUser.put(key, userId);
                }
            }
        }

        List<Lead__c> leadsForRoundRobin = new List<Lead__c>();
        List<Lead__c> stickyEligibilityLeadsToUpdate = new List<Lead__c>();

        for (Lead__c l : leads) {
            String phone  = l.Phone__c;
            String source = l.Source_Bucket__c;
            Boolean assigned = false;

            if (!String.isBlank(phone) && !String.isBlank(source)) {
                String key = phone.trim() + '|' + source.trim();
                Id existingUser = phoneSourceToUser.get(key);
                if (existingUser != null) {
                    if (isEligibility) {
                        l.GP_User__c = existingUser;
                        stickyEligibilityLeadsToUpdate.add(l);
                    } else {
                        l.OwnerId = existingUser;
                    }
                    assigned = true;
                }
            }

            if (!assigned) {
                leadsForRoundRobin.add(l);
            }
        }

        if (isEligibility && !stickyEligibilityLeadsToUpdate.isEmpty()) {
            update stickyEligibilityLeadsToUpdate;
        }

        if (!leadsForRoundRobin.isEmpty()) {
            RoundRobinService.assignForLeads(leadsForRoundRobin, normType);
        }
    }
}