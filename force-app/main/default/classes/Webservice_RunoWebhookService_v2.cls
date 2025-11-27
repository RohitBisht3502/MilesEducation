@RestResource(urlMapping='/runo/call-log/*')
global without sharing class Webservice_RunoWebhookService_v2 {
    
    global class Ack {
        public Boolean success;
        public String message;
    }
    
    @HttpPost
    global static void receive() {

        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody != null ? req.requestBody.toString() : null;
        Map<String, String> headers = req.headers;
        Map<String, String> params  = req.params;
        String url = req.requestURI;

        String envelope = JSON.serialize(new Map<String, Object>{
            'url'     => url,
            'headers' => headers,
            'params'  => params,
            'body'    => body
        });

        // Load Metadata Config
        External_Service_Config__mdt cfg;
        try {
            cfg = [ SELECT Api_Key__c, Api_Key_Header__c, Is_Active__c  FROM External_Service_Config__mdt  WHERE DeveloperName = 'Runo_Webhook'  LIMIT 1 ];

        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, null, 'Config load error: '+e.getMessage(), 'Failed', 500));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 500, false, 'Config load error');
            return;
        }

        String expectedHeader = cfg != null ? cfg.Api_Key_Header__c : null;
        String expectedToken  = cfg != null ? cfg.Api_Key__c        : null;
        String providedToken  = (headers != null && expectedHeader != null) ? headers.get(expectedHeader) : null;

        // Optional security check
        // (disabled for now as per your current code)

        Object parsed;
        try { parsed = JSON.deserializeUntyped(body); } 
        catch (Exception e) { parsed = null; }

        try {
			CallReceiveWrapper wrapperObj 	= CallReceiveWrapper.parse(body);
            Call_Log__c callLogObj 			= new Call_Log__c();  
            wrapperObj.userPhone			= formatPhoneNo(wrapperObj.userPhone);
            wrapperObj.phoneNumber			= formatPhoneNo(wrapperObj.phoneNumber);
            if(wrapperObj.type == 'outgoing') {
                Call_Log__c existingCallLogObj = [Select Id, Lead__c from Call_Log__c 
                                          		  where User_Phone__c LIKE: ('%' + wrapperObj.userPhone) AND Phone_Number__c LIKE: ('%' + wrapperObj.phoneNumber)
                                          		  AND Status__c = 'In Progress' ORDER BY CreatedDate DESC LIMIT 1];
                callLogObj.Id	    = existingCallLogObj.Id;
                callLogObj.Lead__c	= existingCallLogObj.Lead__c;
                callLogObj 		    = populateCallLogRecord(callLogObj, wrapperObj);                
            } else {
                List<Lead__c> existingLeads = [Select Id from Lead__c where Phone__c LIKE: ('%' + wrapperObj.phoneNumber) ORDER BY CreatedDate DESC LIMIT 1];
                System.debug('existingLeads  >>> '+existingLeads);
                if(!existingLeads.isEmpty()){
                    callLogObj.Lead__c	= existingLeads[0].Id;
                }
                callLogObj 		        = populateCallLogRecord(callLogObj, wrapperObj);
            }   

            upsert callLogObj;
            System.debug(callLogObj);
            System.debug(callLogObj.Lead__c);
			
            Integer dur = callLogObj.Duration_Seconds__c != null ? Integer.valueOf(callLogObj.Duration_Seconds__c) : null;
            // Un-comment this if event publisher is required Type__c
            RunoEventPublisher.publishCallCompleted(callLogObj.Call_Id__c, dur, callLogObj.Lead__c, callLogObj.Candidate__c, callLogObj.Phone_Number__c, callLogObj.Type__c, 'Completed');
            
            RunoEnquiryTaskService.handle(callLogObj.Type__c, callLogObj.Phone_Number__c, callLogObj.Customer_Name__c, null);

            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), null, 'Received', 200));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 200, true, 'OK');

        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog('Runo Webhook', envelope, JSON.serialize(parsed), 'Upsert error: '+e.getMessage(), 'Failed', 500));
            IntegrationLogUtil.insertLogs(logs);
            send(res, 500, false, 'Upsert error');
        }
    }
    
    public static Call_Log__c populateCallLogRecord(Call_Log__c callLogObj, CallReceiveWrapper wrapperObj) {
        callLogObj.Call_Id__c 			= wrapperObj.callId;
        callLogObj.Process_Id__c 		= wrapperObj.processId;
        callLogObj.User_Phone__c 		= wrapperObj.userPhone;
        callLogObj.Phone_Number__c 		= wrapperObj.phoneNumber;
        callLogObj.Customer_Id__c 		= wrapperObj.customerId;
        callLogObj.Customer_Name__c 	= wrapperObj.name;
        callLogObj.Called_By__c 		= wrapperObj.calledBy;
        callLogObj.Caller_Id__c 		= wrapperObj.callerId;
        callLogObj.Tag__c 				= wrapperObj.tag;
        callLogObj.Type__c 				= wrapperObj.type;
        callLogObj.Duration_Seconds__c 	= wrapperObj.duration;
        callLogObj.Created_At__c 		= fromEpoch(wrapperObj.createdAt);
        callLogObj.Start_Time__c 		= fromEpoch(wrapperObj.startTime);
        callLogObj.Status__c 			= 'Completed';
        return callLogObj;
    }
    
    
    private static Datetime fromEpoch(Long s) {
        return s == null ? null : Datetime.newInstance(1970, 1, 1, 0, 0, 0).addSeconds((Integer)s);
    }
    
    
    private static String formatPhoneNo(String phoneNo) {
        if (String.isBlank(phoneNo)) return null;
        phoneNo = phoneNo.replaceAll('[^0-9]', '');
        if (phoneNo.startsWith('91')) phoneNo = phoneNo.substring(2);
        if (phoneNo.length() > 10) phoneNo = phoneNo.right(10);
        return phoneNo;
    }
    

    private static void send(RestResponse res, Integer code, Boolean ok, String msg) {
        Ack a = new Ack();
        a.success = ok;
        a.message = msg;
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(a));
    }

}