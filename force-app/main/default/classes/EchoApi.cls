/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : 
 * Author          : Rohit Singh Bisht
 * Created Date    : Jan 21, 2026
 */
@RestResource(urlMapping='/echo/*')
global without sharing class EchoApi {

    private static Boolean isLeadStage(String level) {
        Set<String> leadStages = new Set<String>{ 'M1','M2','M3','M3+','M3++','M4-','M4','M5','M6','M7' };
        return leadStages.contains(level);
    }

    @HttpPost
    global static void doPost() {

        RestRequest req = RestContext.request;
        String body = req.requestBody.toString();
        String reqPayload = body;
        String resPayload;
        Integer statusCode = 200;

        try {

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);

            String uuid    = (String) payload.get('uuid');
            String level   = (String) payload.get('level');
            String program = (String) payload.get('program');

            if (String.isBlank(uuid) || String.isBlank(level) || String.isBlank(program)) {

                statusCode = 400;
                resPayload = 'UUID or Level or Program missing';

                IntegrationLogUtil.insertLog('GP Level Update API', reqPayload, resPayload, 'Validation Failed', 'Failed', statusCode);

                RestContext.response.statusCode = statusCode;
                RestContext.response.responseBody = Blob.valueOf(resPayload);
                return;
            }

            if (isLeadStage(level)) {

                Lead l = [SELECT Id FROM Lead WHERE UUID__c = :uuid LIMIT 1];

                Lead__c lead = [SELECT Id, Stage__c FROM Lead__c WHERE Candidate__c = :l.Id AND Course__c = :program LIMIT 1];

                lead.Stage__c = level;
                update lead;

            } else {

                Account acc = [SELECT Id FROM Account WHERE UUID__c = :uuid LIMIT 1];

                Course_Enrolled__c ce = [SELECT Id, Stages__c FROM Course_Enrolled__c WHERE Student__c = :acc.Id AND Course__c = :program LIMIT 1];

                ce.Stages__c = level;
                update ce;
            }

            Map<String, Object> resp = new Map<String, Object>{
                'uuid' => uuid,
                'level' => level,
                'program' => program,
                'status' => 'success'
            };

            resPayload = JSON.serialize(resp);

            IntegrationLogUtil.insertLog('GP Level Update API', reqPayload, resPayload, 'Success', 'Success', 200);

            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(resPayload);

        } catch (Exception e) {

            statusCode = 500;
            resPayload = 'Error: ' + e.getMessage();

            IntegrationLogUtil.insertLog('GP Level Update API', reqPayload, resPayload, 'Unhandled Error', 'Failed', statusCode);

            RestContext.response.statusCode = statusCode;
            RestContext.response.responseBody = Blob.valueOf(resPayload);
        }
    }
}