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

    public class CallHistoryDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Integer durationSeconds;
        @AuraEnabled public String status;
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public String stage;
    }

 public class WebinarMemberDTO {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String webinarName;
    @AuraEnabled public String attendanceStatus;
    @AuraEnabled public Datetime createdDate;
}


public class EventDTO {
    @AuraEnabled public Id id;
    @AuraEnabled public String subject;
    @AuraEnabled public String attendance;
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

    @AuraEnabled(cacheable=true)
    public static List<CallHistoryDTO> getCallHistory(Id recordId) {
        if (recordId == null) return new List<CallHistoryDTO>();

        List<Call_Log__c> logs = new List<Call_Log__c>();
        if (recordId.getSObjectType() == Lead__c.SObjectType) {
            logs = [SELECT Id, Start_Time__c, CreatedDate, Duration_Seconds__c, Status__c, L1__c, L2__c, Stage__c FROM Call_Log__c WHERE Lead__c = :recordId ORDER BY Start_Time__c DESC NULLS LAST, CreatedDate DESC LIMIT 10];
        } else if (recordId.getSObjectType() == Course_Enrolled__c.SObjectType) {
            logs = [SELECT Id, Start_Time__c, CreatedDate, Duration_Seconds__c, Status__c, L1__c, L2__c, Stage__c FROM Call_Log__c WHERE Course_Enrolled__c = :recordId ORDER BY Start_Time__c DESC NULLS LAST, CreatedDate DESC LIMIT 10];
        } else {
            return new List<CallHistoryDTO>();
        }

        List<CallHistoryDTO> res = new List<CallHistoryDTO>();
        for (Call_Log__c cl : logs) {
            CallHistoryDTO dto = new CallHistoryDTO();
            dto.id = cl.Id;
            dto.startTime = cl.Start_Time__c;
            dto.createdDate = cl.CreatedDate;
            dto.durationSeconds = cl.Duration_Seconds__c != null ? Integer.valueOf(cl.Duration_Seconds__c) : 0;
            dto.status = cl.Status__c;
            dto.l1 = cl.L1__c;
            dto.l2 = cl.L2__c;
            dto.stage = cl.Stage__c;
            res.add(dto);
        }

        return res;
    }


@AuraEnabled(cacheable=true)
public static List<EventDTO> getLeadEvents(Id recordId) {

    if (recordId == null) return new List<EventDTO>();

    List<Event> events = [
        SELECT Id,
               Subject,
               Candidate_Attendance__c
        FROM Event
        WHERE WhatId = :recordId
        ORDER BY ActivityDateTime DESC
        LIMIT 20
    ];

    List<EventDTO> res = new List<EventDTO>();

    for (Event e : events) {
        EventDTO dto = new EventDTO();
        dto.id = e.Id;
        dto.subject = e.Subject;
        dto.attendance = e.Candidate_Attendance__c;
        res.add(dto);
    }

    return res;
}


@AuraEnabled(cacheable=true)
public static Id getLatestUntrackedCallLog(Id leadId) {

    List<Call_Log__c> logs = [
        SELECT Id, Untracked__c
        FROM Call_Log__c
        WHERE Lead__c = :leadId
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (!logs.isEmpty() && logs[0].Untracked__c == true) {
        return logs[0].Id;
    }

    return null;
}








@AuraEnabled(cacheable=true)
public static List<WebinarMemberDTO> getWebinarMembers(Id recordId) {

    if (recordId == null) return new List<WebinarMemberDTO>();

  

    List<Webinar_Member__c> members = [
        SELECT Id,
               Name,
               Attendance_Status__c,
               Meeting_Details__c,
               Webinar__c,
               Webinar__r.Name,
               Lead_Owner_at_Registration__c,
               Lead_Owner_During_Webinar__c,
               Lead_Stage_at_Registration__c,
               Lead_Stage_During_Webinar__c,
               CreatedDate
        FROM Webinar_Member__c
        WHERE Lead__c = :recordId
        ORDER BY CreatedDate DESC
        LIMIT 10
    ];

    List<WebinarMemberDTO> res = new List<WebinarMemberDTO>();

    for (Webinar_Member__c wm : members) {
        WebinarMemberDTO dto = new WebinarMemberDTO();
        dto.id = wm.Id;
        // dto.name = wm.Name;
        dto.webinarName = wm.Webinar__r != null ? wm.Webinar__r.Name : '';
        dto.attendanceStatus = wm.Attendance_Status__c;
        dto.createdDate = wm.CreatedDate;
        res.add(dto);
    }

    return res;
}




    @AuraEnabled
    public static String allocateLeadNow(Id recordId) {
        Schema.SObjectType sType;
        String customerName;
        String customerPhone;
        String customerEmail;
        External_Service_Config__mdt cfg;
        AllocationDTO payload;
        String bodyJson;
        HttpRequest req;
        Http http;
        String resBody;
        Integer statusCode;
        Boolean isSuccess;
        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        sType = recordId.getSObjectType();
        customerName = null;
        customerPhone = null;
        customerEmail = null;
        isSuccess = false;

        if (sType == Lead__c.SObjectType) {
            Lead__c leadRecord = [SELECT Id, Name, Phone__c, Email__c FROM Lead__c WHERE Id = :recordId LIMIT 1];
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

       if (String.isBlank(customerPhone)) {
    throw new AuraHandledException('Phone number is required for call allocation.');
}

if (String.isBlank(customerName)) {
    customerName = 'Unknown Caller';
}


        cfg = getRunoConfig();
        payload = buildAllocationPayload(customerName, customerPhone, customerEmail);
        bodyJson = JSON.serialize(payload);

        req = buildHttpRequest(cfg, bodyJson);
        http = new Http();

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

       if (isSuccess) {
    String callId = extractCallId(resBody); // 🔹 GET callId from Runo response
    createCallLog(recordId, payload.assignedTo, customerPhone, callId);
}

        return resBody;
    }

    public static External_Service_Config__mdt getRunoConfig() {
        External_Service_Config__mdt cfg = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'RunoAllocationAPI' LIMIT 1];

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


    public static void createCallLog(
    Id recordId,
    String userPhone,
    String phone,
    String callId
) {
    Call_Log__c callLog = new Call_Log__c(
        User_Phone__c  = userPhone,
        Phone_Number__c = phone,
        Status__c       = 'In Progress',
        Call_Id__c      = callId,          // ✅ SAVE CALL ID
        Untracked__c    = true
    );

    if (recordId != null) {
        SObjectType sType = recordId.getSObjectType();

        if (sType == Lead__c.SObjectType) {
            callLog.Lead__c = recordId;

            Id candidateId = Utility.candidateByPhone(phone);
            if (candidateId != null) {
                callLog.Candidate__c = candidateId;
            }

        } 
        else if (sType == Course_Enrolled__c.SObjectType) {
            callLog.Course_Enrolled__c = recordId; // ✅ LINK COURSE ENROLLED
        }
    }

    insert callLog;
}

@AuraEnabled
public static void updateCallFeedback1(
    Id recordId,
    String callId,
    String feedback,
    Datetime nextFollowUpDate,
    String l1,
    String l2,
    String stage,
    String level,
    Boolean notifyMe
) {

    if (String.isBlank(feedback)) {
        return;
    }

    SObjectType sType = recordId != null ? recordId.getSObjectType() : null;
    Boolean isLead = (sType == Lead__c.SObjectType);
    Boolean isCallLogRec = (sType == Call_Log__c.SObjectType);

    // 🔹 Find Call Log
    Call_Log__c logRecord = findCallLog(recordId, callId);

    if (logRecord == null) {
        throw new AuraHandledException('No Call Log found for this record.');
    }

    if (l1 == 'Connected' && String.isBlank(stage)) {
        throw new AuraHandledException('Stage is required when L1 is Connected.');
    }

    // =============================
    // 🔹 Update Call Log
    // =============================

    logRecord.Feedback__c            = feedback;
    logRecord.Next_Follow_Up_Date__c = nextFollowUpDate;
    logRecord.L1__c                  = l1;
    logRecord.L2__c                  = l2;
    logRecord.Notify_Me__c           = notifyMe;
    logRecord.Untracked__c           = false;

    if (!String.isBlank(stage)) {
        logRecord.Stage__c = stage;
    }

    // 🔹 Store Course in Call Log
    if (!String.isBlank(level)) {
        logRecord.Course__c = level;
    }

    update logRecord;

    // =============================
    // 🔹 Identify Related Lead
    // =============================

    Id leadIdToUpdate;

    if (logRecord.Lead__c != null) {
        leadIdToUpdate = logRecord.Lead__c;
    } else if (isLead && recordId != null) {
        leadIdToUpdate = recordId;
    }

    // =============================
    // 🔹 Update Lead
    // =============================

    if (leadIdToUpdate != null) {

        Lead__c leadUpdate = new Lead__c(
            Id = leadIdToUpdate,
            Next_Follow_Up_Date__c = nextFollowUpDate,
            Notify_Me__c = notifyMe
        );

        // Update Stage
        if (!String.isBlank(stage)) {
            leadUpdate.Stage__c = stage;
        }

        // Update Course + Record Type
        if (!String.isBlank(level)) {

            leadUpdate.Course__c = level;

            // Fetch matching Record Type
            List<RecordType> rts = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Lead__c'
                AND Name = :level
                AND IsActive = true
                LIMIT 1
            ];

            if (!rts.isEmpty()) {
                leadUpdate.RecordTypeId = rts[0].Id;
            }
        }

        update leadUpdate;
    }
}


    
  @AuraEnabled
public static void updateCallFeedback(String jsonBody) {

    CallFeedbackRequest request;
    try {
        request = (CallFeedbackRequest) JSON.deserialize(jsonBody, CallFeedbackRequest.class);
    } catch (Exception e) {
        throw new AuraHandledException('Invalid JSON format: ' + e.getMessage());
    }

    if (request == null || String.isBlank(request.feedback)) {
        return;
    }

    Id recordId = !String.isBlank(request.recordId) ? (Id)request.recordId : null;
    String callId = request.callId;

    //  Find Call Log
    Call_Log__c logRecord = findCallLog(recordId, callId);

    if (logRecord == null) {
        throw new AuraHandledException('No Call Log found for this record.');
    }

    //  Validation
    if (request.l1 == 'Connected' && String.isBlank(request.stage)) {
        throw new AuraHandledException('Stage is required when L1 is Connected.');
    }

    

    logRecord.Feedback__c            = request.feedback;
    logRecord.Next_Follow_Up_Date__c = request.nextFollowUpDate;
    logRecord.L1__c                  = request.l1;
    logRecord.L2__c                  = request.l2;
    logRecord.Notify_Me__c           = request.notifyMe;
    logRecord.Untracked__c           = false;

    if (!String.isBlank(request.stage)) {
        logRecord.Stage__c = request.stage;
    }

    if (!String.isBlank(request.level)) {
        logRecord.Course__c = request.level;
    }

    update logRecord;

    // =============================
    // 🔹 Identify related Lead
    // =============================

    Id leadIdToUpdate;

    if (logRecord.Lead__c != null) {
        leadIdToUpdate = logRecord.Lead__c;
    } else if (recordId != null && recordId.getSObjectType() == Lead__c.SObjectType) {
        leadIdToUpdate = recordId;
    }

    if (leadIdToUpdate == null) return;

    // =============================
    // 🔹 Update Lead (ONCE)
    // =============================

    Lead__c leadUpdate = new Lead__c(
        Id = leadIdToUpdate,
        Next_Follow_Up_Date__c = request.nextFollowUpDate,
        Notify_Me__c = request.notifyMe
    );

    if (!String.isBlank(request.stage)) {
        leadUpdate.Stage__c = request.stage;
    }

    if (!String.isBlank(request.level)) {

        leadUpdate.Course__c = request.level;

        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead__c'
            AND Name = :request.level
            AND IsActive = true
            LIMIT 1
        ];

        if (!rts.isEmpty()) {
            leadUpdate.RecordTypeId = rts[0].Id;
        }
    }

    update leadUpdate;
}



public static Call_Log__c findCallLog(Id recordId, String callId) {

    Call_Log__c logRecord;

    // Best match → callId
    if (String.isNotBlank(callId)) {
        List<Call_Log__c> logs = [
            SELECT Id, Phone_Number__c, Lead__c, Course_Enrolled__c
            FROM Call_Log__c
            WHERE Call_Id__c = :callId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!logs.isEmpty()) logRecord = logs[0];
    }

    //  Course Enrolled fallback
    if (logRecord == null &&
        recordId != null &&
        recordId.getSObjectType() == Course_Enrolled__c.SObjectType) {

        List<Call_Log__c> logs = [
            SELECT Id, Phone_Number__c, Lead__c, Course_Enrolled__c
            FROM Call_Log__c
            WHERE Course_Enrolled__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!logs.isEmpty()) logRecord = logs[0];
    }

    //  Course Enrolled fallback
    if (logRecord == null &&
        recordId != null &&
        recordId.getSObjectType() == Call_Log__c.SObjectType) {

        List<Call_Log__c> logs = [
            SELECT Id,Phone_Number__c, Lead__c, Course_Enrolled__c
            FROM Call_Log__c
            WHERE Id = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!logs.isEmpty()) logRecord = logs[0];
    }

    //  Lead fallback
    if (logRecord == null &&
        recordId != null &&
        recordId.getSObjectType() == Lead__c.SObjectType) {

        List<Call_Log__c> logs = [
            SELECT Id, Phone_Number__c, Lead__c, Course_Enrolled__c
            FROM Call_Log__c
            WHERE Lead__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!logs.isEmpty()) logRecord = logs[0];
    }

    //  Mark all phone logs as tracked
    if (logRecord != null && String.isNotBlank(logRecord.Phone_Number__c)) {
        List<Call_Log__c> phoneLogs = [
            SELECT Id, Untracked__c
            FROM Call_Log__c
            WHERE Phone_Number__c = :logRecord.Phone_Number__c
            AND Untracked__c = true
        ];
        for (Call_Log__c cl : phoneLogs) {
            cl.Untracked__c = false;
        }
        if (!phoneLogs.isEmpty()) update phoneLogs;
    }

    return logRecord;
}



@AuraEnabled(cacheable=true)
public static Map<String, List<String>> getStageLevelValues(Id recordId) {

    Map<String, List<String>> result = new Map<String, List<String>>();

    result.put(
        'stage',
        getPicklistValues(Lead__c.Stage__c)
    );

    result.put(
        'level',
        getPicklistValues(Lead__c.Course__c)
    );

    return result;
}


private static List<String> getPicklistValues(Schema.SObjectField fieldRef) {

    List<String> values = new List<String>();
    Schema.DescribeFieldResult field = fieldRef.getDescribe();

    for (Schema.PicklistEntry pe : field.getPicklistValues()) {
        if (pe.isActive()) {
            values.add(pe.getLabel());
        }
    }
    return values;
}



// private static List<String> getPicklistValues(Schema.SObjectField fieldRef) {

//     List<String> values = new List<String>();

//     Schema.DescribeFieldResult field = fieldRef.getDescribe();

//     for (Schema.PicklistEntry pe : field.getPicklistValues()) {
//         if (pe.isActive()) {
//             values.add(pe.getLabel());   // or pe.getValue() if you prefer API value
//         }
//     }

//     return values;
// }

 @AuraEnabled
public static String allocateCourseNow(Id recordId) {

    if (recordId == null) {
        throw new AuraHandledException('Course Enrolled Id is required.');
    }

    Course_Enrolled__c ce = [
        SELECT Id, Name, Phone__c, Student__r.Name, Student__r.Email__c
        FROM Course_Enrolled__c
        WHERE Id = :recordId
        LIMIT 1
    ];

    if (String.isBlank(ce.Phone__c)) {
        throw new AuraHandledException('Course Enrolled must have Phone.');
    }

    External_Service_Config__mdt cfg = getRunoConfig();

    AllocationDTO payload = buildAllocationPayload(
        ce.Student__r != null ? ce.Student__r.Name : ce.Name,
        ce.Phone__c,
        ce.Student__r != null ? ce.Student__r.Email__c : null
    );

    String bodyJson = JSON.serialize(payload);
    HttpRequest req = buildHttpRequest(cfg, bodyJson);

    Http http = new Http();
    String resBody;
    Integer statusCode;
    Boolean isSuccess = false;

    List<Integration_Log__c> logs = new List<Integration_Log__c>();

    try {
        HttpResponse res = http.send(req);
        statusCode = res.getStatusCode();
        resBody = res.getBody();
        isSuccess = statusCode >= 200 && statusCode < 300;

        logs.add(
            IntegrationLogUtil.buildLog(
                'Runo Allocation API - Course Enrolled',
                bodyJson,
                resBody,
                isSuccess ? null : 'HTTP ' + statusCode,
                isSuccess ? 'Success' : 'Failed',
                statusCode
            )
        );
    } catch (Exception e) {
        logs.add(
            IntegrationLogUtil.buildLog(
                'Runo Allocation API - Course Enrolled',
                bodyJson,
                null,
                e.getMessage(),
                'Failed',
                null
            )
        );
        IntegrationLogUtil.insertLogs(logs);
        throw e;
    }

    IntegrationLogUtil.insertLogs(logs);

   if (isSuccess) {
    String callId = extractCallId(resBody); // ✅ extract callId
    createCallLog(recordId, payload.assignedTo, ce.Phone__c, callId);
}


    return resBody;
}

private static String extractCallId(String resBody) {
    if (String.isBlank(resBody)) return null;

    try {
        Map<String, Object> m =
            (Map<String, Object>) JSON.deserializeUntyped(resBody);
        return (String) m.get('callId');
    } catch (Exception e) {
        System.debug('Failed to extract callId: ' + e.getMessage());
        return null;
    }
}




@AuraEnabled
public static void updateCourseCallFeedback(String jsonBody) {

    CallFeedbackRequest request;
    try {
        request = (CallFeedbackRequest) JSON.deserialize(jsonBody, CallFeedbackRequest.class);
    } catch (Exception e) {
        throw new AuraHandledException('Invalid JSON: ' + e.getMessage());
    }

    if (request == null || String.isBlank(request.recordId)) {
        throw new AuraHandledException('Record Id missing.');
    }

    Id recordId = (Id) request.recordId;

    Call_Log__c logRecord = findCallLog(recordId, request.callId);

    if (logRecord == null) {
        throw new AuraHandledException('No Call Log found.');
    }

    // 🔹 Update Call Log
    logRecord.Feedback__c            = request.feedback;
    logRecord.Next_Follow_Up_Date__c = request.nextFollowUpDate;
    logRecord.L1__c                  = request.l1;
    logRecord.L2__c                  = request.l2;
    if (!String.isBlank(request.stage)) {
        logRecord.Stage__c = request.stage;
    }
    logRecord.Notify_Me__c           = request.notifyMe;
    logRecord.Untracked__c           = false;

    update logRecord;

    // 🔹 Update Course Enrolled
   Course_Enrolled__c ceUpdate = new Course_Enrolled__c(
    Id = recordId,
    Due_Date__c = request.nextFollowUpDate != null
        ? request.nextFollowUpDate.date()
        : null
);
    if (!String.isBlank(request.stage)) {
        ceUpdate.Stages__c = request.stage;
    }


    update ceUpdate;
}




    public class CallFeedbackRequest {
        public String recordId;
        public String callId;
        public String feedback;
        public Datetime nextFollowUpDate;
        public String l1;
        public String l2;
        public String stage;
        public String level;
        public Boolean notifyMe;
    }
}