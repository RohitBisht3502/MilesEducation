@RestResource(urlMapping='/us-pathway/status')
global without sharing class Webhook_CourseEnrolledStatusUpdate {

    private static final String SERVICE_NAME = 'Course Enrolled Status Update';
    private static final String USP_RT_NAME = 'US Pathway';
    private static final String USP_RT_DEV_NAME = 'US_Pathway';

    @HttpPost
    global static ApiResponse updateStatus() {
        ApiResponse response = new ApiResponse();

        RestRequest req = RestContext.request;
        String requestPayload = truncate(req != null && req.requestBody != null ? req.requestBody.toString() : null);

        if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
            response.success = false;
            response.message = 'Empty request body';
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        RequestWrapper input;
        try {
            input = (RequestWrapper) JSON.deserialize(req.requestBody.toString(), RequestWrapper.class);
        } catch (Exception e) {
            response.success = false;
            response.message = 'Invalid JSON: ' + e.getMessage();
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        if (String.isBlank(input.uuid) || String.isBlank(input.level) || String.isBlank(input.program)) {
            response.success = false;
            response.message = 'uuid, level and program are required';
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        Id uspRecordTypeId = getUspRecordTypeId();
        if (uspRecordTypeId == null) {
            response.success = false;
            response.message = 'USP Pathway record type not found for Course Enrolled';
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 500);
            return response;
        }

        try {
            Account student = [SELECT Id FROM Account WHERE UUID__c = :input.uuid LIMIT 1];
            Course_Enrolled__c ce = [SELECT Id, Stages__c, RecordTypeId FROM Course_Enrolled__c WHERE Student__c = :student.Id AND Course__c = :input.program AND RecordTypeId = :uspRecordTypeId LIMIT 1];

            ce.Stages__c = input.level;
            update ce;

            response.success = true;
            response.message = 'Course enrolled status updated';
            response.uuid = input.uuid;
            response.level = input.level;
            response.program = input.program;
            response.courseEnrolledId = ce.Id;

            IntegrationLogUtil.insertLog(
                SERVICE_NAME,
                requestPayload,
                truncate(JSON.serialize(response)),
                response.message,
                'Success',
                200
            );
            return response;

        } catch (QueryException qe) {
            response.success = false;
            response.message = 'No student/course enrolled found for given uuid and program';
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 404);
            return response;

        } catch (DmlException de) {
            response.success = false;
            response.message = 'DML error while updating status: ' + de.getMessage();
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 500);
            return response;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Unhandled error: ' + e.getMessage();
            IntegrationLogUtil.insertLog(SERVICE_NAME, requestPayload, null, response.message, 'Failed', 500);
            return response;
        }
    }

    private static Id getUspRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byName = Schema.SObjectType.Course_Enrolled__c.getRecordTypeInfosByName();
        if (byName != null && byName.containsKey(USP_RT_NAME)) {
            return byName.get(USP_RT_NAME).getRecordTypeId();
        }

        Map<String, Schema.RecordTypeInfo> byDevName = Schema.SObjectType.Course_Enrolled__c.getRecordTypeInfosByDeveloperName();
        if (byDevName != null && byDevName.containsKey(USP_RT_DEV_NAME)) {
            return byDevName.get(USP_RT_DEV_NAME).getRecordTypeId();
        }

        return null;
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000)
            ? value.substring(0, 3000)
            : value;
    }

    global class RequestWrapper {
        public String uuid;
        public String level;
        public String program;
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public String uuid;
        public String level;
        public String program;
        public Id courseEnrolledId;
    }
}
