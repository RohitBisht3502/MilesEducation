public with sharing class RunoEventPublisher {
    public static void publishCallCompleted(String callId, Integer durationSeconds, Id leadId,Id candidateId, String phone, String callType, String status) {
        Runo_Call_Completed__e evt = new Runo_Call_Completed__e(
            Call_Id__c          = callId,
            Duration_Seconds__c = durationSeconds,
            Lead_Id__c          = leadId == null ? null : (String)leadId,
            Candidate_Id__c     = leadId == null ? null : (String)candidateId,
            Phone__c            = phone,
            Status__c           = status,
            Type__c             = callType
        );
        Database.SaveResult sr = EventBus.publish(evt);
    }
}