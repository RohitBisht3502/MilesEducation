/*
    Author       : ROHIT SINGH BISHT
    Description  : REST API to update UUID__c on any SObject using Salesforce Id and UUID from request body.
*/
@RestResource(urlMapping='/uuid/update')
global without sharing class Webservice_UUIDUpdateService {

    /*
        DTO for incoming request body
        Example JSON:
        {
            "salesforceId": "a01XXXXXXXXXXXXXXX",
            "uuid": "123e4567-e89b-12d3-a456-426614174000"
        }
    */
    global class UUIDUpdateRequestDTO {
        public String salesforceId;
        public String uuid;
    }

    /*
        DTO for API response
    */
    global class UUIDUpdateResponseDTO {
        public Boolean success;
        public String message;
        public Id recordId;
        public String sobjectType;
    }

    @HttpPost
    global static UUIDUpdateResponseDTO updateUUIDForRecord() {
        // Prepare response object
        UUIDUpdateResponseDTO resp = new UUIDUpdateResponseDTO();
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String rawRequestBody = (req != null && req.requestBody != null) ? req.requestBody.toString() : null;

        System.debug('UUID Update Service - Raw Request Body ==> ' + rawRequestBody);

        if (req == null || req.requestBody == null || String.isBlank(rawRequestBody)) {
            resp.success = false;
            resp.message = 'Request body is empty.';
            res.statusCode = 400;

            IntegrationLogUtil.insertLog( 'UUID Updater Service', rawRequestBody, null, 'Empty request body', 'Failed', 400);

            return resp;
        }

        UUIDUpdateRequestDTO input;
        try {
            input = (UUIDUpdateRequestDTO) JSON.deserialize(rawRequestBody, UUIDUpdateRequestDTO.class);
            System.debug('UUID Update Service - Parsed Request ==> ' + input);
            System.debug('UUID Update Service - salesforceId ==> ' + input.salesforceId);
            System.debug('UUID Update Service - uuid         ==> ' + input.uuid);
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Invalid JSON: ' + e.getMessage();
            res.statusCode = 400;

            IntegrationLogUtil.insertLog( 'UUID Updater Service', rawRequestBody, null, 'Invalid JSON: ' + e.getMessage(),'Failed', 400);

            return resp;
        }

        if (input == null || String.isBlank(input.salesforceId) || String.isBlank(input.uuid)) {
            resp.success = false;
            resp.message = 'Both salesforceId and uuid are required.';
            res.statusCode = 400;

            IntegrationLogUtil.insertLog( 'UUID Updater Service',  rawRequestBody, null, 'Missing required fields: salesforceId and/or uuid','Failed',400);

            return resp;
        }

        Id recordId;
        try {
            recordId = (Id) input.salesforceId;
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Invalid Salesforce Id: ' + input.salesforceId;
            res.statusCode = 400;

            IntegrationLogUtil.insertLog('UUID Updater Service', rawRequestBody, null, 'Invalid Salesforce Id: ' + input.salesforceId, 'Failed', 400);

            return resp;
        }

        // Resolve SObject type from Id prefix
        Schema.SObjectType sType = recordId.getSObjectType();
        String sobjectTypeName   = String.valueOf(sType);
        System.debug('UUID Update Service - Detected SObject Type ==> ' + sobjectTypeName);

        // Create a dynamic SObject, set Id and UUID__c
        SObject sobj = sType.newSObject(recordId);
        sobj.put('UUID__c', input.uuid);

        System.debug('UUID Update Service - SObject to Update ==> ' + sobj);

        try {
            update sobj;

            resp.success     = true;
            resp.message     = 'UUID__c updated successfully.';
            resp.recordId    = recordId;
            resp.sobjectType = sobjectTypeName;
            res.statusCode   = 200;

            String responseJson = JSON.serialize(resp);
            System.debug('UUID Update Service - Success Response ==> ' + responseJson);

            IntegrationLogUtil.insertLog('UUID Updater Service', rawRequestBody, (responseJson != null && responseJson.length() > 3000 ? responseJson.substring(0, 3000) : responseJson), 'UUID__c updated successfully.', 'Success', 200 );

        } catch (DmlException d) {
            resp.success     = false;
            resp.message     = 'DML error while updating UUID__c: ' + d.getMessage();
            resp.recordId    = recordId;
            resp.sobjectType = sobjectTypeName;
            res.statusCode   = 500;

            System.debug('UUID Update Service - DMLException ==> ' + d.getMessage());

            IntegrationLogUtil.insertLog('UUID Updater Service', rawRequestBody, null, 'DML error while updating UUID__c: ' + d.getMessage(), 'Failed', 500 );

        } catch (Exception e) {
            resp.success     = false;
            resp.message     = 'Unexpected error: ' + e.getMessage();
            resp.recordId    = recordId;
            resp.sobjectType = sobjectTypeName;
            res.statusCode   = 500;

            System.debug('UUID Update Service - Exception ==> ' + e.getMessage());

            IntegrationLogUtil.insertLog( 'UUID Updater Service', rawRequestBody, null, 'Unexpected error: ' + e.getMessage(), 'Failed', 500 );
        }

        return resp;
    }
}