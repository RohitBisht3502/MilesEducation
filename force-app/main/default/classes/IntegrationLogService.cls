// Utility service to capture Integration_Log__c entries for all eligibility-related integrations.
public without sharing class IntegrationLogService {

    public class LogParams {
        public String integrationType;
        public String status;
        public String requestPayload;
        public String responsePayload;
        public Integer statusCode;
        public String errorMessage;
    }

    public static void log(LogParams params) {
        if (params == null) return;
        try {
            Integration_Log__c rec = new Integration_Log__c();
            rec.Integration_Type__c = params.integrationType;
            rec.Status__c = params.status;
            rec.Request_Payload__c = params.requestPayload;
            rec.Response_Payload__c = params.responsePayload;
            rec.Status_Code__c = params.statusCode;
            rec.Error_Message__c = params.errorMessage;
            insert rec;
        } catch (Exception e) {
            System.debug('IntegrationLogService.log failed: ' + e.getMessage());
        }
    }

    public static void log(String integrationType, String status, String requestPayload, String responsePayload, Integer statusCode, String errorMessage) {
        LogParams lp = new LogParams();
        lp.integrationType = integrationType;
        lp.status = status;
        lp.requestPayload = requestPayload;
        lp.responsePayload = responsePayload;
        lp.statusCode = statusCode;
        lp.errorMessage = errorMessage;
        log(lp);
    }
}