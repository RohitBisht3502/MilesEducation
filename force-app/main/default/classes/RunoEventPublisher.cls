public with sharing class RunoEventPublisher {
    public static void publishCallCompleted(String callId, Integer durationSeconds, Id leadId, String phone, String status) {
        Runo_Call_Completed__e evt = new Runo_Call_Completed__e(
            Call_Id__c          = callId,
            Duration_Seconds__c = durationSeconds,
            Lead_Id__c          = leadId == null ? null : (String)leadId,
            Phone__c            = phone,
            Status__c           = status
        );
        Database.SaveResult sr = EventBus.publish(evt);
    }
}