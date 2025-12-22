public with sharing class TableauScriptsTest {
    
    
    
    public static void testTableauScripts() {
        
        Set<Id> LeadIds = new Set<Id>();
        
        for(Enquiry__C enq : [Select Lead__c from Enquiry__c where ownerId!= null] ){
            LeadIds.add(enq.Lead__c);
        }
        
        List<AggregateResult> LeadList = [Select Count_distinct(Id) totalCount from Lead__c where id in: LeadIds and Stage__c  In ('M7+','M7') and ownerId != null];
        
        
        Integer leadCount = (Integer) leadList[0].get('totalCount');
        System.debug('Lead Count = ' + leadCount);
        


        
    }
    
    
    
    
}