public without sharing class LeadQueueItemDTO {

    // I am using this DTO as the single source of truth for
    // queue items coming from both Lead__c and Call Logs.
    // I will also send this same object directly to my LWC.

    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String phone;
    @AuraEnabled public String course;
    @AuraEnabled public String city;
    @AuraEnabled public String stage; 
    @AuraEnabled public String source;  
    @AuraEnabled public String displayStage;
    @AuraEnabled public Datetime createdDate;
    @AuraEnabled public Boolean iscallLog;
    @AuraEnabled public Integer priority;
    @AuraEnabled public String primaryTag;
    @AuraEnabled public String sourceTag;
    @AuraEnabled public String roleTag;
    @AuraEnabled public String bucketTag;
    @AuraEnabled public Datetime nextFollowUpDate;
}
