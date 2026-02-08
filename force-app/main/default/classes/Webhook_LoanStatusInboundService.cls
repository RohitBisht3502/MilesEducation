/*
    Author       : ROHIT SINGH BISHT
    Description  : Updates Loan__c status from inbound webhook payload
*/
@RestResource(urlMapping='/loan/status/update')
global without sharing class Webhook_LoanStatusInboundService {

    global class LoanStatusRequest {
        public String miles_loan_code;
        public String loan_status;
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public Id loanId;
    }

    @HttpPost
    global static ApiResponse doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        ApiResponse out = new ApiResponse();
        out.success = false;

        String serviceName = 'Loan Status Inbound';
        String requestPayload = truncate(
            req != null && req.requestBody != null ? req.requestBody.toString() : null
        );

        Integer statusCode = 500;

        try {
            if (req == null || req.requestBody == null || String.isBlank(req.requestBody.toString())) {
                statusCode = 400;
                out.message = 'Empty request body';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                res.statusCode = statusCode;
                return out;
            }

            LoanStatusRequest payload;
            try {
                payload = (LoanStatusRequest) JSON.deserialize(req.requestBody.toString(), LoanStatusRequest.class);
            } catch (Exception ex) {
                statusCode = 400;
                out.message = 'Invalid JSON: ' + ex.getMessage();
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                res.statusCode = statusCode;
                return out;
            }

            if (payload == null || String.isBlank(payload.miles_loan_code) || String.isBlank(payload.loan_status)) {
                statusCode = 400;
                out.message = 'miles_loan_code and loan_status are required';
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                res.statusCode = statusCode;
                return out;
            }

            String loanCode = payload.miles_loan_code.trim();
            List<Loan__c> loans = [SELECT Id FROM Loan__c WHERE miles_loan_code__c = :loanCode LIMIT 1];

            if (loans.isEmpty()) {
                statusCode = 404;
                out.message = 'Loan not found for miles_loan_code: ' + payload.miles_loan_code;
                IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
                res.statusCode = statusCode;
                return out;
            }

            Loan__c loanToUpdate = loans[0];
            loanToUpdate.put('loan_status__c', payload.loan_status.trim());
            update loanToUpdate;

            statusCode = 200;
            out.success = true;
            out.message = 'Loan status updated successfully';
            out.loanId = loanToUpdate.Id;

            IntegrationLogUtil.insertLog(
                serviceName,
                requestPayload,
                truncate(JSON.serialize(out)),
                out.message,
                'Success',
                statusCode
            );
        } catch (DmlException de) {
            statusCode = 500;
            out.message = 'DML error while updating loan: ' + de.getMessage();
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
        } catch (Exception e) {
            statusCode = 500;
            out.message = 'Unhandled error: ' + e.getMessage();
            IntegrationLogUtil.insertLog(serviceName, requestPayload, null, out.message, 'Failed', statusCode);
        }

        if (res != null) res.statusCode = statusCode;
        return out;
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000)
            ? value.substring(0, 3000)
            : value;
    }
}