public without sharing class TriggerRoundRobinService {
    public static Boolean running = false;

    public static void handleBeforeInsert(List<Lead__c> newLeads) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        running = true;
        try { RoundRobinService.assignForLeads(newLeads,'Round Robin'); }
        finally { running = false; }
    }

    public static void handleBeforeUpdate(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        List<Lead__c> toProcess = new List<Lead__c>();
        for (Lead__c nl : newLeads) {
            Lead__c ol = oldMap.get(nl.Id);
          if (nl.City__c != ol.City__c || nl.Source__c != ol.Source__c) {
                toProcess.add(nl);
           }
        }
        if (toProcess.isEmpty()) return;
        running = true;
        try { RoundRobinService.assignForLeads(toProcess,'Round Robin'); }
        finally { running = false; }
    }
}