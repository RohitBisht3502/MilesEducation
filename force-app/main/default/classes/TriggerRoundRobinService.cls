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
            RoundRobinAssigner.assignWithStickyAndRoundRobin(
                (List<SObject>) newLeads,
                'Lead__c',
                'Round Robin'
            );
        } finally {
            running = false;
        }
    }

    public static void handleBeforeUpdate(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        if (running || newLeads == null || newLeads.isEmpty() || oldMap == null) return;

        RoundRobinConfigProvider.Config cfg =
            RoundRobinConfigProvider.getConfig('Lead__c', 'Round Robin');

        if (cfg == null) return;

        List<Lead__c> toProcess = new List<Lead__c>();

        for (Lead__c nl : newLeads) {
            Lead__c ol = oldMap.get(nl.Id);
            if (ol == null) continue;

            Boolean changed = false;

            if (!String.isBlank(cfg.cityField)) {
                String nCity = String.valueOf(nl.get(cfg.cityField));
                String oCity = String.valueOf(ol.get(cfg.cityField));
                if (nCity != oCity) changed = true;
            }

            if (!cfg.ignoreSource && !String.isBlank(cfg.sourceField)) {
                String nSrc = String.valueOf(nl.get(cfg.sourceField));
                String oSrc = String.valueOf(ol.get(cfg.sourceField));
                if (nSrc != oSrc) changed = true;
            }

            if (!String.isBlank(cfg.courseField)) {
                String nCourse = String.valueOf(nl.get(cfg.courseField));
                String oCourse = String.valueOf(ol.get(cfg.courseField));
                if (nCourse != oCourse) changed = true;
            }

            if (changed) toProcess.add(nl);
        }

        if (toProcess.isEmpty()) return;

        running = true;
        try {
            RoundRobinAssigner.assignWithStickyAndRoundRobin(
                (List<SObject>) toProcess,
                'Lead__c',
                'Round Robin'
            );
        } finally {
            running = false;
        }
    }
}