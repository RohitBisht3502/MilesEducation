/**
 * Batch class to handle Condition 1:
 * After Lead is created, Stage is null and Next_Follow_Up_Date__c is empty 
 * till half hour of creation, assign to Queue and update Stage to Q1
 */
global class LeadInitialQueueAssignmentBatch implements Database.Batchable<SObject>, Schedulable {
    
    // Update with your Limited Queue's Developer Name
    private static final String LIMITED_QUEUE_NAME = 'High_Priority_Bangalore';
    
    // Batch start method
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime timeLimit = Datetime.now().addMinutes(-30);
        
        String query = 'SELECT Id, OwnerId, Queue_Stage__c, Next_Follow_Up_Date__c ' +
                      'FROM Lead__c ' +
                      'WHERE Queue_Stage__c = null ' +
                      'AND Next_Follow_Up_Date__c = null ' +
                      'AND CreatedDate <= :timeLimit' + 
            		  'AND Source_Bucket__c = \'Bucket 1\'';
        
        return Database.getQueryLocator(query);
    }
    
    // Batch execute method
    global void execute(Database.BatchableContext bc, List<Lead__c> leads) {
        // Get Queue ID
        List<Group> queues = [SELECT Id FROM Group 
                             WHERE Type = 'Queue' AND DeveloperName = :LIMITED_QUEUE_NAME 
                             LIMIT 1];
        
        if (queues.isEmpty()) {
            System.debug('Queue not found: ' + LIMITED_QUEUE_NAME);
            return;
        }
        
        Id queueId = queues[0].Id;
        List<Lead__c> updatedLeads = new List<Lead__c>();
        
        for (Lead__c lead : leads) {
            if (lead.OwnerId != queueId) {
                lead.OwnerId = queueId;
                lead.Queue_Stage__c = 'Q1';
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
        Database.executeBatch(new LeadInitialQueueAssignmentBatch(), 100);
    }
}