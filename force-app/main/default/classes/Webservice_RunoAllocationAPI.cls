/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class Webservice_RunoAllocationAPI implements Database.AllowsCallouts {

    public class CustomerDTO {
        public String name;
        public String phoneNumber;
        public String email;
    }

    public class AllocationDTO {
        public CustomerDTO customer;
        public String processName;
        public String assignedTo;
        public Integer priority;
        public String notes;
        public List<Object> userFields;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getL1L2Values() {
        Map<String, List<String>> mapValues = new Map<String, List<String>>();

        mapValues.put('Connected', new List<String>{
            'Discussed',
            'Request Call Back',
            'Not Eligible',
            'Wrong Number',
            'Language Barrier',
            'Visit Confirmed',
            'Visit Completed',
            'Visit Rescheduled',
            'Visit Cancelled',
            'Visit Booked By Mistake',
            'Google Meet Completed',
            'Google Meet Rescheduled',
            'Google Meet Cancelled',
            'Attended And Disconnected',
            'Voice Mail',
            'Not Interested (DND)'
        });

        mapValues.put('Not-Connected', new List<String>{
            'Not Lifting',
            'Switched Off',
            'Not Reachable',
            'Busy',
            'Invalid Number'
        });

        return mapValues;
    }

    @AuraEnabled
    public static String allocateLeadNow(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        Schema.SObjectType sType = recordId.getSObjectType();

        String customerName;
        String customerPhone;
        String customerEmail;
        Lead__c leadCForCallLog;

        if (sType == Lead__c.SObjectType) {
            Lead__c leadRecord = [SELECT Id, Name, Phone__c, Email__c FROM Lead__c WHERE Id = :recordId LIMIT 1];
            leadCForCallLog = leadRecord;
            customerName  = leadRecord.Name;
            customerPhone = leadRecord.Phone__c;
            customerEmail = leadRecord.Email__c;
        } else if (sType == Lead.SObjectType) {
            Lead leadRecord = [SELECT Id, Name, Phone, Email FROM Lead WHERE Id = :recordId LIMIT 1];
            customerName  = leadRecord.Name;
            customerPhone = leadRecord.Phone;
            customerEmail = leadRecord.Email;
        } else if (sType == Account.SObjectType) {
            Account acc = [SELECT Id, Name, Phone, Email__c FROM Account WHERE Id = :recordId LIMIT 1];
            customerName  = acc.Name;
            customerPhone = acc.Phone;
            customerEmail = acc.Email__c;
        } else if (sType == Call_Log__c.SObjectType) {
            Call_Log__c cl = [SELECT Id, Customer_Name__c, Phone_Number__c FROM Call_Log__c WHERE Id = :recordId LIMIT 1];
            customerName  = cl.Customer_Name__c;
            customerPhone = cl.Phone_Number__c;
            customerEmail = null;
        } else {
            throw new AuraHandledException('Unsupported object for Runo allocation.');
        }

        if (String.isBlank(customerName) || String.isBlank(customerPhone)) {
            throw new AuraHandledException('Record must have Name and Phone.');
        }

        External_Service_Config__mdt cfg = getRunoConfig();

        AllocationDTO payload = buildAllocationPayload(customerName, customerPhone, customerEmail);
        String bodyJson = JSON.serialize(payload);

        HttpRequest req = buildHttpRequest(cfg, bodyJson);
        Http http = new Http();

        String resBody;
        Integer statusCode;
        Boolean isSuccess = false;
        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        try {
            HttpResponse res = http.send(req);
            statusCode = res != null ? res.getStatusCode() : null;
            resBody = res != null ? res.getBody() : null;
            isSuccess = statusCode != null && statusCode >= 200 && statusCode < 300;

            logs.add(
                IntegrationLogUtil.buildLog(
                    'Runo Allocation API',
                    bodyJson,
                    resBody,
                    isSuccess ? null : 'HTTP ' + String.valueOf(statusCode),
                    isSuccess ? 'Success' : 'Failed',
                    statusCode
                )
            );
        } catch (Exception e) {
            logs.add(
                IntegrationLogUtil.buildLog(
                    'Runo Allocation API',
                    bodyJson,
                    null,
                    'Exception: ' + e.getMessage(),
                    'Failed',
                    null
                )
            );
            IntegrationLogUtil.insertLogs(logs);
            throw e;
        }

        IntegrationLogUtil.insertLogs(logs);

        if (isSuccess && leadCForCallLog != null) {
            createCallLog(leadCForCallLog, payload.assignedTo);
        }

        return resBody;
    }

    public static External_Service_Config__mdt getRunoConfig() {
        External_Service_Config__mdt cfg = [ SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c 
            FROM External_Service_Config__mdt WHERE DeveloperName = 'RunoAllocationAPI' LIMIT 1];

        if (cfg == null ||
            !cfg.Is_Active__c ||
            String.isBlank(cfg.Endpoint_URL__c) ||
            String.isBlank(cfg.Http_Method__c)) {
            throw new AuraHandledException('RunoAllocationAPI config missing/invalid.');
        }

        return cfg;
    }

    public static AllocationDTO buildAllocationPayload(String name, String phone, String email) {
        AllocationDTO payload = new AllocationDTO();
        payload.customer = new CustomerDTO();
        payload.customer.name = name;
        payload.customer.phoneNumber = phone;
        payload.customer.email = email;
        payload.processName = 'Salesforce Process';
        payload.assignedTo = '8123191110';
        payload.priority = 3;
        payload.notes = 'Outbound call from Miles Force';
        payload.userFields = new List<Object>();
        return payload;
    }

    public static HttpRequest buildHttpRequest(External_Service_Config__mdt cfg, String bodyJson) {
        HttpRequest req = new HttpRequest();

        String endpoint = cfg.Endpoint_URL__c;
        if (!endpoint.contains('isAutoDialLead=')) {
            endpoint += (endpoint.contains('?') ? '&' : '?') + 'isAutoDialLead=true';
        }

        req.setEndpoint(endpoint);
        req.setMethod(cfg.Http_Method__c);
        req.setHeader('Content-Type', 'application/json');

        if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
            req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }

        req.setTimeout(60000);
        req.setBody(bodyJson);
        return req;
    }

    public static void createCallLog(Lead__c leadRecord, String userPhone) {
        Id candidateId = Utility.candidateByPhone(leadRecord.Phone__c);

        Call_Log__c callLog = new Call_Log__c(
            Lead__c = leadRecord.Id,
            User_Phone__c = userPhone,
            Phone_Number__c = leadRecord.Phone__c,
            Status__c = 'In Progress'
        );

        if (candidateId != null) {
            callLog.Candidate__c = candidateId;
        }

        insert callLog;
    }

    @AuraEnabled
    public static void updateCallFeedback(Id leadId,String callId,String feedback,Datetime nextFollowUpDate,String l1,String l2,String stage,String level) {
        System.debug('UPDATE FB => Lead:' + leadId + ' Call:' + callId);

        if (String.isBlank(feedback)) {
            return;
        }

        Call_Log__c logRecord = findCallLog(leadId, callId);

        if (logRecord == null) {
            throw new AuraHandledException('No Call Log found for this Lead.');
        }

        logRecord.Feedback__c = feedback;
        logRecord.Next_Follow_Up_Date__c = nextFollowUpDate;
        logRecord.L1__c = l1;
        logRecord.L2__c = l2;
        logRecord.Stage__c = stage;
       // logRecord.Course__c = level;

        update logRecord;

        if (leadId != null) {
            Lead__c leadUpdate = new Lead__c(
                Id = leadId,
                Stage__c = stage,
                // Course__c = level,
                Next_Follow_Up_Date__c = nextFollowUpDate
            );
            update leadUpdate;
        }
    }

    public static Call_Log__c findCallLog(Id leadId, String callId) {
        Call_Log__c logRecord = null;

        if (!String.isBlank(callId)) {
            List<Call_Log__c> logsByCall = [SELECT Id FROM Call_Log__c WHERE Call_Id__c = :callId ORDER BY CreatedDate DESC LIMIT 1];

            if (!logsByCall.isEmpty()) {
                logRecord = logsByCall[0];
            }
        }

        if (logRecord == null && leadId != null) {
            List<Call_Log__c> logsByLead = [ SELECT Id FROM Call_Log__c WHERE Lead__c = :leadId ORDER BY CreatedDate DESC LIMIT 1 ];

            if (!logsByLead.isEmpty()) {
                logRecord = logsByLead[0];
            }
        }

        return logRecord;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getStageLevelValues() {
        Map<String, List<String>> result = new Map<String, List<String>>();

        List<String> stageValues = new List<String>();
        Schema.DescribeFieldResult stageField = Lead__c.Stage__c.getDescribe();
        for (Schema.PicklistEntry pe : stageField.getPicklistValues()) {
            if (pe.isActive()) {
                stageValues.add(pe.getLabel());
            }
        }

        List<String> levelValues = new List<String>();
        Schema.DescribeFieldResult levelField = Lead__c.Course__c.getDescribe();
        for (Schema.PicklistEntry pe : levelField.getPicklistValues()) {
            if (pe.isActive()) {
                levelValues.add(pe.getLabel());
            }
        }

        result.put('stage', stageValues);
        result.put('level', levelValues);

        return result;
    }
}