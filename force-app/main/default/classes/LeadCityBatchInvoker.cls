public without sharing class LeadCityBatchInvoker {
    public static void runAfterCommit(Set<Id> leadIds) {
        if (leadIds != null && !leadIds.isEmpty()) {
            Database.executeBatch(new LeadCityUpdateBatch(leadIds), 50);
        }
    }
}