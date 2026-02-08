/**
 * Batch class to handle Condition 2:
 * If Stage is Q1 and Next_Follow_Up_Date__c is still empty 
 * till one hour after creation, assign to current user and update Stage to Q2
 */
global class LeadFollowUpAssignmentBatch implements Database.Batchable<SObject>, Schedulable {
    
    // Update with your Public Queue's Developer Name
    private static final String PUBLIC_QUEUE_NAME = 'Public_Queue';
    
    // Batch start method
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime timeLimit = Datetime.now().addMinutes(-60);
        
        String query = 'SELECT Id, OwnerId, Queue_Stage__c, Next_Follow_Up_Date__c ' +
                      'FROM Lead__c ' +
                      'WHERE Queue_Stage__c = \'Q1\' ' +
                      'AND Next_Follow_Up_Date__c = null ' +
                      'AND CreatedDate <= :timeLimit ' +
            		  'AND Source_Bucket__c = \'Bucket 1\' ';
        
        return Database.getQueryLocator(query);
    }
    
    // Batch execute method
    global void execute(Database.BatchableContext bc, List<Lead__c> leads) {
        // Get Queue ID
        List<Group> queues = [SELECT Id FROM Group 
                             WHERE Type = 'Queue' AND DeveloperName = :PUBLIC_QUEUE_NAME 
                             LIMIT 1];
        
        if (queues.isEmpty()) {
            System.debug('Queue not found: ' + PUBLIC_QUEUE_NAME);
            return;
        }
        
        Id queueId = queues[0].Id;
        List<Lead__c> updatedLeads = new List<Lead__c>();
        
        for (Lead__c lead : leads) {
            if (lead.OwnerId != queueId) {
                lead.OwnerId = queueId;
                lead.Queue_Stage__c = 'Q2';
                updatedLeads.add(lead);
            }
        }
        
        if (!updatedLeads.isEmpty()) {
            update updatedLeads;
        }
    }
    
    global void finish(Database.BatchableContext bc) {}
    
    // Schedulable execute method
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new LeadFollowUpAssignmentBatch(), 100);
    }
}