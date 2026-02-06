/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class TriggerRoundRobinService {

    public static Boolean running = false;

    public static void handleBeforeInsert(List<Lead__c> newLeads) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        running = true;
        try {
            // Group leads by type (MCOM vs CC - Pre Enrollment)
            List<Lead__c> mcomLeads = new List<Lead__c>();
            List<Lead__c> regularLeads = new List<Lead__c>();
            
            for (Lead__c lead : newLeads) {
                if ('MCOM'.equalsIgnoreCase(lead.Course__c)) {
                    mcomLeads.add(lead);
                } else {
                    regularLeads.add(lead);
                }
            }
            
            // Process MCOM leads
            if (!mcomLeads.isEmpty()) {
                RoundRobinAssigner.assignWithStickyAndRoundRobin(
                    (List<SObject>) mcomLeads,
                    'Lead__c',
                    'MCOM'
                );
            }
            
            // Process regular leads
            if (!regularLeads.isEmpty()) {
                RoundRobinAssigner.assignWithStickyAndRoundRobin(
                    (List<SObject>) regularLeads,
                    'Lead__c',
                    'CC - Pre Enrollment'
                );
            }
        } finally {
            running = false;
        }
    }

    public static void handleBeforeUpdate(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        if (running || newLeads == null || newLeads.isEmpty() || oldMap == null) return;

        List<Lead__c> mcomToProcess = new List<Lead__c>();
        List<Lead__c> regularToProcess = new List<Lead__c>();

        for (Lead__c nl : newLeads) {
            Lead__c ol = oldMap.get(nl.Id);
            if (ol == null) continue;

            Boolean isMCOM = 'MCOM'.equalsIgnoreCase(nl.Course__c);
            String type = isMCOM ? 'MCOM' : 'CC - Pre Enrollment';
            
            RoundRobinConfigProvider.Config cfg =
                RoundRobinConfigProvider.getConfig('Lead__c', type);

            if (cfg == null) continue;

            Boolean changed = false;

            // Check city change
            if (!String.isBlank(cfg.cityField)) {
                String nCity = String.valueOf(nl.get(cfg.cityField));
                String oCity = String.valueOf(ol.get(cfg.cityField));
                if (nCity != oCity) changed = true;
            }

            // Check source change
            if (!cfg.ignoreSource && !String.isBlank(cfg.sourceField)) {
                String nSrc = String.valueOf(nl.get(cfg.sourceField));
                String oSrc = String.valueOf(ol.get(cfg.sourceField));
                if (nSrc != oSrc) changed = true;
            }

            // Check course change
            if (!String.isBlank(cfg.courseField)) {
                String nCourse = String.valueOf(nl.get(cfg.courseField));
                String oCourse = String.valueOf(ol.get(cfg.courseField));
                if (nCourse != oCourse) changed = true;
            }

            if (changed) {
                if (isMCOM) {
                    mcomToProcess.add(nl);
                } else {
                    regularToProcess.add(nl);
                }
            }
        }

        running = true;
        try {
            // Process MCOM leads
            if (!mcomToProcess.isEmpty()) {
                RoundRobinAssigner.assignWithStickyAndRoundRobin(
                    (List<SObject>) mcomToProcess,
                    'Lead__c',
                    'MCOM'
                );
            }

            // Process regular leads
            if (!regularToProcess.isEmpty()) {
                RoundRobinAssigner.assignWithStickyAndRoundRobin(
                    (List<SObject>) regularToProcess,
                    'Lead__c',
                    'CC - Pre Enrollment'
                );
            }
        } finally {
            running = false;
        }
    }
}
