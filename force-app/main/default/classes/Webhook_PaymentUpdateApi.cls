@RestResource(urlMapping='/payment/update')
global without sharing class Webhook_PaymentUpdateApi {

    @HttpPost
    global static ApiResponse updatePayment() {

        ApiResponse response = new ApiResponse();

        RestRequest req = RestContext.request;
        String serviceName = 'Webhook Payment Update';
        String requestPayload =
            truncate(req != null && req.requestBody != null ? req.requestBody.toString() : null);

        //  Empty request body check
        if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
            response.success = false;
            response.message = 'Empty request body';

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                null,
                response.message,
                'Failed',
                400
            );
            return response;
        }

        PaymentRequest paymentReq;

        //  JSON deserialize
        try {
            paymentReq = (PaymentRequest) JSON.deserialize(
                req.requestBody.toString(),
                PaymentRequest.class
            );
        } catch (Exception e) {
            response.success = false;
            response.message = 'Invalid JSON: ' + e.getMessage();

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                null,
                response.message,
                'Failed',
                400
            );
            return response;
        }

        // Validation
        if (String.isBlank(paymentReq.transactionId)) {
            response.success = false;
            response.message = 'Transaction Id is required';

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                null,
                response.message,
                'Failed',
                400
            );
            return response;
        }


//         if (String.isBlank(paymentReq.createdBy)) {
//     response.success = false;
//     response.message = 'Created By username is required';
//     return response;
// }


        try {
            // ️⃣ Fetch Transcation
            Transcation__c txn = [
                SELECT Id, Payment_Received__c, Status__c, Transcation_Id__c
                FROM Transcation__c
                WHERE Transcation_Id__c = :paymentReq.transactionId
                LIMIT 1
            ];



            //Update fields
          txn.Payment_Received__c = paymentReq.paymentReceived;
txn.Status__c = 'Received';

txn.Purchase_Orders__c = paymentReq.purchaseId;
           

update txn;


// Fetch Purchase Order amounts
Purchase_Order__c poData = [
    SELECT Id, Lead__c, Net_Payable_Amount__c, Total_Payment_Received__c
    FROM Purchase_Order__c
    WHERE Id = :paymentReq.purchaseId
    LIMIT 1
];

// Fetch Lead to update picklist
Lead__c ld = [
    SELECT Id, Payment_Received__c
    FROM Lead__c
    WHERE Id = :poData.Lead__c
    LIMIT 1
];

Decimal netPayable = poData.Net_Payable_Amount__c == null ? 0 : poData.Net_Payable_Amount__c;
Decimal totalReceived = poData.Total_Payment_Received__c == null ? 0 : poData.Total_Payment_Received__c;


// Decide picklist value
if (totalReceived == 0) {
    ld.Payment_Received__c = 'Not Received';
}
else if (totalReceived < netPayable) {
    ld.Payment_Received__c = 'Partially Received';
}
else if (totalReceived >= netPayable) {
    ld.Payment_Received__c = 'Fully Received';
}

// ️ Update Lead
update ld;


            response.success = true;
            response.message = 'Payment updated successfully';
            // response.recordId = txn.Id;

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                truncate(JSON.serialize(response)),
                response.message,
                'Success',
                200
            );

        } catch (QueryException qe) {
            response.success = false;
            response.message = 'No transaction found for given Transaction Id';

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                null,
                response.message,
                'Failed',
                404
            );

        } catch (DmlException de) {
            response.success = false;
            response.message = 'DML error while updating payment: ' + de.getMessage();

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                null,
                response.message,
                'Failed',
                500
            );

        } catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                null,
                response.message,
                'Failed',
                500
            );
        }

        return response;
    }

    // Request Wrapper
    global class PaymentRequest {
        public String transactionId;
        public Decimal paymentReceived;
       
         public Id purchaseId;
       

    }

    // Response Wrapper
    global class ApiResponse {
        public Boolean success;
        public String message;
      
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000)
            ? value.substring(0, 3000)
            : value;
    }
}