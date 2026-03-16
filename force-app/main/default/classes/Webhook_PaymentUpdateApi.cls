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
        String loanKey = !String.isBlank(paymentReq.loanId)
            ? paymentReq.loanId
            : paymentReq.loan_id;
        String transactionType = !String.isBlank(paymentReq.transactionType)
            ? paymentReq.transactionType
            : paymentReq.transaction_type;

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
            Purchase_Order__c po = [
                SELECT Id, Net_Payable_Amount__c, Lead__c, Lead__r.Payment_Received__c, Lead__r.Stage__c, Lead__r.Course__c
                FROM Purchase_Order__c
                WHERE Purchase_Order_Id__c = :purchaseKey
                LIMIT 1
            ];

            if (!String.isBlank(loanKey)) {
                Id resolvedLoanId = resolveLoanId(loanKey);
                if (resolvedLoanId == null) {
                    response.success = false;
                    response.message = 'No loan found for given Loan Id';
                    IntegrationLogUtil.insertLog(serviceName, requestPayload, null, response.message, 'Failed', 404);
                    return response;
                }

                if (isSubvention(transactionType)) {
                    insert new Transcation__c(
                        Purchase_Orders__c = po.Id,
                        Loan__c = resolvedLoanId,
                        Payment__c = paymentReq.paymentReceived,
                        Status__c = 'Received',
                        Transcation_Id__c = paymentReq.transactionId
                    );
                } else {
                    Transcation__c txn = [
                        SELECT Id, Payment__c, Status__c, Transcation_Id__c, Loan__c, Purchase_Orders__c
                        FROM Transcation__c
                        WHERE Purchase_Orders__c = :po.Id
                        AND Loan__c = :resolvedLoanId
                        AND Status__c != 'Received'
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];

                    txn.Payment__c = paymentReq.paymentReceived;
                    txn.Status__c = 'Received';
                    txn.Transcation_Id__c = paymentReq.transactionId;
                    update txn;
                }
            } else {
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
            }

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
                Lead__c leadToUpdate = new Lead__c(Id = po.Lead__c);
                Boolean shouldUpdateLead = false;

                if (!(leadStatus == 'Partially Received' && po.Lead__r.Payment_Received__c == 'Partially Received')) {
                    leadToUpdate.Payment_Received__c = leadStatus;
                    shouldUpdateLead = true;
                }

                if (leadStatus == 'Partially Received') {
                    String targetStage;
                    if (po.Lead__r.Course__c == 'US Pathway') {
                        targetStage = 'U7';
                    } else if (po.Lead__r.Course__c == 'CPA' || po.Lead__r.Course__c == 'CMA' || po.Lead__r.Course__c == 'CAIRA') {
                        targetStage = 'M7';
                    }

                    if (targetStage != null && po.Lead__r.Stage__c != targetStage) {
                        leadToUpdate.Stage__c = targetStage;
                        shouldUpdateLead = true;
                    }
                }

                if (shouldUpdateLead) {
                    update leadToUpdate;
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
        public String loanId;
        public String loan_id;
        public String transactionType;
        public String transaction_type;
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

    private static Boolean isSubvention(String transactionType) {
        return !String.isBlank(transactionType) && transactionType.trim().toLowerCase() == 'subvention';
    }

    private static Id resolveLoanId(String loanKey) {
        if (String.isBlank(loanKey)) {
            return null;
        }

        try {
            Id sfLoanId = Id.valueOf(loanKey);
            List<Loan__c> loansBySfId = [SELECT Id FROM Loan__c WHERE Id = :sfLoanId LIMIT 1];
            if (!loansBySfId.isEmpty()) {
                return loansBySfId[0].Id;
            }
        } catch (Exception e) {
            // Fall back to external loan id lookup.
        }

        List<Loan__c> loansByExternalId = [SELECT Id FROM Loan__c WHERE Loan_Id__c = :loanKey LIMIT 1];
        return loansByExternalId.isEmpty() ? null : loansByExternalId[0].Id;
    }
}
