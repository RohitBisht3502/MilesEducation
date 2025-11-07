public with sharing class IntegrationLogUtil {

    // Use a safe picklist value
    public static Integration_Log__c buildLog(
        String integrationType,
        String requestPayload,
        String responsePayload,
        String errorMessage,
        String status,
        Integer statusCode
    ) {
        Integration_Log__c log = new Integration_Log__c();

        // Ensure integrationType is valid for restricted picklist
        List<Schema.PicklistEntry> picklistEntries = Integration_Log__c.Integration_Type__c.getDescribe().getPicklistValues();
        List<String> allowedValues = new List<String>();

        for (Schema.PicklistEntry pe : picklistEntries) {
            allowedValues.add(pe.getValue());
        }

        if (!allowedValues.contains(integrationType)) {
            integrationType = allowedValues.isEmpty() ? null : allowedValues[0];
        }

        log.Integration_Type__c = integrationType;
        log.Request_Payload__c  = requestPayload;
        log.Response_Payload__c = responsePayload;
        log.Error_Message__c    = errorMessage;
        log.Status__c           = status;
        log.Status_Code__c      = statusCode;
        return log;
    }

    public static void insertLog(
        String integrationType,
        String requestPayload,
        String responsePayload,
        String errorMessage,
        String status,
        Integer statusCode
    ) {
        try {
            insert buildLog(integrationType, requestPayload, responsePayload, errorMessage, status, statusCode);
        } catch (Exception e) {
            System.debug('Failed to insert Integration_Log__c: ' + e.getMessage());
        }
    }

    public static void insertLogs(List<Integration_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        try {
            insert logs;
        } catch (Exception e) {
            System.debug('Failed to insert Integration_Log__c list: ' + e.getMessage());
        }
    }
}