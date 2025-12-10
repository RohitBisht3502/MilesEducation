/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class TriggerRoundRobinService {
    private static Boolean running = false;

    public static void handleBeforeInsert(List<Lead__c> newLeads) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        running = true;
        try {
            RoundRobinAssigner.assignLeadsWithStickyAndRoundRobin(newLeads, 'Round Robin');
        } finally {
            running = false;
        }
    }

    public static void handleBeforeUpdate(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        List<Lead__c> toProcess = new List<Lead__c>();
        for (Lead__c nl : newLeads) {
            Lead__c ol = oldMap.get(nl.Id);
            if (nl.City__c != ol.City__c || nl.Source_Bucket__c != ol.Source_Bucket__c) {
                toProcess.add(nl);
            }
        }
        if (toProcess.isEmpty()) return;
        running = true;
        try {
            RoundRobinAssigner.assignLeadsWithStickyAndRoundRobin(toProcess, 'Round Robin');
        } finally {
            running = false;
        }
    }
}