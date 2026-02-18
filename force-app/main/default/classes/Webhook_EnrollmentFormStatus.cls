@RestResource(urlMapping='/Enrollment/Status/*')
global without sharing class Webhook_EnrollmentFormStatus {

    @HttpPost
    global static ApiResponse updateStatus() {
        String requestBody = RestContext.request.requestBody.toString();

        try {
            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(requestBody);

            if (!payload.containsKey('purchaseOrderId') || !payload.containsKey('status')) {
                IntegrationLogUtil.insertLog(
                    'Enrollment Webhook',
                    requestBody,
                    'Missing required fields',
                    null,
                    'Failed',
                    400
                );

                RestContext.response.statusCode = 400;
                return new ApiResponse(false, 'Missing required fields', null, null);
            }

            String externalPOId = String.valueOf(payload.get('purchaseOrderId'));
            String status = String.valueOf(payload.get('status')).trim();

            Set<String> allowedStatuses = new Set<String>{ 'Draft', 'Sent', 'Accepted' };
            if (!allowedStatuses.contains(status)) {
                IntegrationLogUtil.insertLog(
                    'Enrollment Webhook',
                    requestBody,
                    'Invalid status value: ' + status,
                    'Invalid picklist value received',
                    'Failed',
                    400
                );

                RestContext.response.statusCode = 400;
                return new ApiResponse(false, 'Invalid status value: ' + status, externalPOId, status);
            }

            List<Purchase_Order__c> poList = [
                SELECT Id, Lead__c
                FROM Purchase_Order__c
                WHERE Purchase_Order_Id__c = :externalPOId
                LIMIT 1
            ];

            if (poList.isEmpty()) {
                IntegrationLogUtil.insertLog(
                    'Enrollment Webhook',
                    requestBody,
                    'Purchase order id not found',
                    null,
                    'Failed',
                    404
                );

                RestContext.response.statusCode = 404;
                return new ApiResponse(false, 'Purchase order id not found', externalPOId, status);
            }

            Purchase_Order__c po = poList[0];
            po.Enrollment_Status__c = status;
            update po;

            if (po.Lead__c != null) {
                update new Lead__c(
                    Id = po.Lead__c,
                    enrollment_status__c = status
                );
            }

            IntegrationLogUtil.insertLog(
                'Enrollment Webhook',
                requestBody,
                'Enrollment status updated successfully',
                null,
                'Success',
                200
            );

            RestContext.response.statusCode = 200;
            return new ApiResponse(true, 'Enrollment status updated successfully', externalPOId, status);

        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Enrollment Webhook',
                requestBody,
                null,
                e.getMessage(),
                'Failed',
                500
            );

            RestContext.response.statusCode = 500;
            return new ApiResponse(false, 'Error: ' + e.getMessage(), null, null);
        }
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public String purchaseOrderId;
        public String status;

        public ApiResponse(Boolean success, String message, String purchaseOrderId, String status) {
            this.success = success;
            this.message = message;
            this.purchaseOrderId = purchaseOrderId;
            this.status = status;
        }
    }
}