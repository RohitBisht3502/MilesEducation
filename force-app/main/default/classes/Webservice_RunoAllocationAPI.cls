public without sharing class Webservice_RunoAllocationAPI implements Database.AllowsCallouts {

    // -------------------------------
    // DTO CLASSES
    // -------------------------------
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


    // ---------------------------------------------------------
    // 1️⃣  FIXED METHOD → STATIC L1 → L2 MAPPING (NO ERRORS)
    // ---------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getL1L2Values() {

        Map<String, List<String>> mapValues = new Map<String, List<String>>();

        // L1 = Connected → L2 values
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
            'Not Interested(DND)'
        });

        // L1 = Not Connected → L2 values
        mapValues.put('Not-Connected', new List<String>{
            'Not Lifting',
            'Switched Off',
            'Not Reachable',
            'Busy',
            'Invalid Number'
        });

        return mapValues;
    }


    // ---------------------------------------------------------
    // 2️⃣  ORIGINAL LEAD ALLOCATION API METHOD (UNCHANGED)
    // ---------------------------------------------------------
    @AuraEnabled
    public static String allocateLeadNow(Id leadId) {

        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required.');
        }

        Lead l = [
            SELECT Id, FirstName, LastName, Name, Phone, MobilePhone, Email
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        String phone = String.isBlank(l.MobilePhone) ? l.Phone : l.MobilePhone;

        if (String.isBlank(l.Name) || String.isBlank(phone) || String.isBlank(l.Email)) {
            throw new AuraHandledException('Lead must have Name, Phone/Mobile, and Email.');
        }

        External_Service_Config__mdt cfg = [
            SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c
            FROM External_Service_Config__mdt
            WHERE DeveloperName = 'RunoAllocationAPI'
            LIMIT 1
        ];

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c) || String.isBlank(cfg.Http_Method__c)) {
            throw new AuraHandledException('RunoAllocationAPI config missing/invalid.');
        }

        Http http = new Http();
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

        AllocationDTO payload = new AllocationDTO();
        payload.customer = new CustomerDTO();
        payload.customer.name = l.Name;
        payload.customer.phoneNumber = phone;
        payload.customer.email = l.Email;
        payload.processName = 'Salesforce Process';
        payload.assignedTo = '8123191110';
        payload.priority = 3;
        payload.notes = 'Outbound call from Miles Force';
        payload.userFields = new List<Object>();

        String bodyJson = JSON.serialize(payload);
        req.setBody(bodyJson);

        String resBody;
        Integer statusCode;

        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        try {
            HttpResponse res = http.send(req);

            statusCode = res != null ? res.getStatusCode() : null;
            resBody = res != null ? res.getBody() : null;

            Boolean ok = statusCode != null && statusCode >= 200 && statusCode < 300;

            logs.add(
                IntegrationLogUtil.buildLog(
                    'Runo Allocation API',
                    bodyJson,
                    resBody,
                    ok ? null : 'HTTP ' + String.valueOf(statusCode),
                    ok ? 'Success' : 'Failed',
                    statusCode
                )
            );
        }
        catch (Exception e) {
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
        return resBody;
    }


    // ---------------------------------------------------------
    // FIXED FEEDBACK METHOD 
    // ---------------------------------------------------------
    @AuraEnabled
    public static void updateCallFeedback(Id leadId, String callId, String feedback, Date nextFollowUpDate, String l1, String l2) {

        System.debug(leadId);
        System.debug(callId);
        System.debug(feedback);
        System.debug(nextFollowUpDate);
        System.debug(l1);
        System.debug(l2);
        if (String.isBlank(feedback)) return;

        Call_Log__c logRecord = null;

        if (!String.isBlank(callId)) {
            List<Call_Log__c> logs = [ SELECT Id FROM Call_Log__c WHERE Call_Id__c = :callId ORDER BY CreatedDate DESC LIMIT 1 ];
            if (!logs.isEmpty()) {
                logRecord = logs[0];
            }
        }

        if (logRecord == null) {
            List<Call_Log__c> recentLogs = [ SELECT Id FROM Call_Log__c WHERE Lead__c = :leadId ORDER BY CreatedDate DESC LIMIT 1 ];
            if (!recentLogs.isEmpty()) {
                logRecord = recentLogs[0];
            }
        }

        if (logRecord == null) {
            throw new AuraHandledException('No Call Log found for this Lead.');
        }

        logRecord.Feedback__c = feedback;
        logRecord.Next_Follow_Up_Date__c = nextFollowUpDate;
        logRecord.L1__c = l1;
        logRecord.L2__c = l2;
        System.debug(logRecord);
        update logRecord;
    }
}