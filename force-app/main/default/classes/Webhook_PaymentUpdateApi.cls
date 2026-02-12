/**
 * Author: Rohit Singh Bisht
 * Created: 2026-02-10
 */
@RestResource(urlMapping='/payment/update')
global without sharing class Webhook_PaymentUpdateApi {

    @HttpPost
    global static ApiResponse updatePayment() {
        ApiResponse response = new ApiResponse();

        RestRequest req = RestContext.request;
        String serviceName = 'Webhook Payment Update';
        String requestPayload = truncate(req != null && req.requestBody != null ? req.requestBody.toString() : null);

        if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
            response.success = false;
            response.message = 'Empty request body';

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        PaymentRequest paymentReq;
        try {
            paymentReq = (PaymentRequest) JSON.deserialize(req.requestBody.toString(), PaymentRequest.class);
        } catch (Exception e) {
            response.success = false;
            response.message = 'Invalid JSON: ' + e.getMessage();

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        String purchaseKey = !String.isBlank(paymentReq.purchaseId)
            ? paymentReq.purchaseId
            : paymentReq.purchase_id;

        if (String.isBlank(purchaseKey)) {
            response.success = false;
            response.message = 'Purchase Order Id is required';

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        if (String.isBlank(paymentReq.transactionId)) {
            response.success = false;
            response.message = 'Transaction Id is required';

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 400);
            return response;
        }

        try {
            Transcation__c txn = [
                SELECT Id, Payment__c, Status__c, Transcation_Id__c,
                    Purchase_Orders__c,
                    Purchase_Orders__r.Purchase_Order_Id__c,
                    Purchase_Orders__r.Net_Payable_Amount__c,
                    Purchase_Orders__r.Total_Payment_Received__c,
                    Purchase_Orders__r.Lead__c,
                    Purchase_Orders__r.Lead__r.Payment_Received__c
                FROM Transcation__c
                WHERE Purchase_Orders__r.Purchase_Order_Id__c = :purchaseKey
                AND Status__c != 'Received'
                AND Transcation_Id__c = null
                AND Payment__c = :paymentReq.paymentReceived
                LIMIT 1
            ];

            txn.Payment__c = paymentReq.paymentReceived;
            txn.Status__c = 'Received';
            txn.Transcation_Id__c = paymentReq.transactionId;
            update txn;

            Purchase_Order__c po = [
                SELECT Id, Net_Payable_Amount__c, Lead__c, Lead__r.Payment_Received__c
                FROM Purchase_Order__c
                WHERE Purchase_Order_Id__c = :purchaseKey
                LIMIT 1
            ];

            AggregateResult ar = [
                SELECT SUM(Payment__c) totalReceived
                FROM Transcation__c
                WHERE Purchase_Orders__c = :po.Id
            ];

            Decimal netPayable = po.Net_Payable_Amount__c == null ? 0 : po.Net_Payable_Amount__c;
            Decimal totalReceived = (Decimal) ar.get('totalReceived');
            totalReceived = totalReceived == null ? 0 : totalReceived;

            String leadStatus;
            if (netPayable > 0 && totalReceived >= netPayable) {
                leadStatus = 'Fully Received';
            } else if (totalReceived > 0) {
                leadStatus = 'Partially Received';
            }

            if (po.Lead__c != null && leadStatus != null) {
                if (!(leadStatus == 'Partially Received' && po.Lead__r.Payment_Received__c == 'Partially Received')) {
                    update new Lead__c(
                        Id = po.Lead__c,
                        Payment_Received__c = leadStatus
                    );
                }
            }

            response.success = true;
            response.message = 'Payment updated successfully';

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
            response.message = 'No transaction found for given Purchase Id';

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 404);
        } catch (DmlException de) {
            response.success = false;
            response.message = 'DML error while updating payment: ' + de.getMessage();

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 500);
        } catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();

            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 500);
        }

        return response;
    }

    global class PaymentRequest {
        public String transactionId;
        public Decimal paymentReceived;
        public String purchaseId;
        public String purchase_id;
    }

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