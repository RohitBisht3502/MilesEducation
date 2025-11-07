public without sharing class TriggerRoundRobinService {
    public static Boolean running = false;

    public static void handleBeforeInsert(List<Lead> newLeads) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        running = true;
        try { RoundRobinService.assignForLeads(newLeads); }
        finally { running = false; }
    }

    public static void handleBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (running || newLeads == null || newLeads.isEmpty()) return;
        List<Lead> toProcess = new List<Lead>();
        for (Lead nl : newLeads) {
            Lead ol = oldMap.get(nl.Id);
          if (nl.City__c != ol.City__c || nl.Coming_From__c != ol.Coming_From__c) {
                toProcess.add(nl);
           }
        }
        if (toProcess.isEmpty()) return;
        running = true;
        try { RoundRobinService.assignForLeads(toProcess); }
        finally { running = false; }
    }
}