// author : Rohit singh bisht
public with sharing class Callout_CreationApiService {
    public class ApiResult {
        public Boolean success;
        public String message;
        public Map<String, Object> data;
    }

    public static void callAndPopulate(Loan__c loan) {
        if (loan == null) return;

        External_Service_Config__mdt cfg = loadConfig();
        if (cfg == null) {
            IntegrationLogUtil.insertLog(
                'Loan Process API',
                null,
                null,
                'Config inactive or missing Endpoint_URL__c',
                'Failed',
                500
            );
            throw new AuraHandledException('Loan vendor service is unavailable. Please try again later.');
        }

        String method = String.isBlank(cfg.Http_Method__c)
            ? 'POST'
            : cfg.Http_Method__c.trim().toUpperCase();

        String provider = resolveRecordTypeDeveloperName(loan.RecordTypeId);

        // Mandatory validation before callout
        validateRequiredFields(loan, provider);

        String candidateUuid = resolveCandidateUuid(loan.Candidate__c);

        Map<String, Object> body = new Map<String, Object>{
            'loan_provider' => provider,
            'miles_uuid' => candidateUuid,
            'program_name' => loan.Program_Name__c,
            'first_name' => loan.First_Name__c,
            'last_name' => loan.First_Name__c,
            'email' => loan.Email__c,
            'mobile' => loan.Mobile__c,
            'amount_requested' => loan.Amount_Requested__c
        };
        body.put('tenure', mapTenure(loan.Tenure__c));

        if (provider == 'AVANSE') {
            body.put(
                'current_address_same_as_permanent',
                loan.Permanent_address_same_as_Current__c
            );

            if (loan.Permanent_address_same_as_Current__c == true) {
                putCurrentAddress(body, loan);
                putPermanentAddress(body, loan);
            } else {
                putCurrentAddress(body, loan);
                putPermanentAddress(body, loan);
            }

            body.put('applying_loan_for', loan.Applying_Loan_For__c);
            body.put('earning_status', mapEarningStatus(loan.Earning_Status__c));
            body.put('occupation_type', mapOccupation(loan.Occupation_Type__c));
            body.put('monthly_income', loan.Monthly_Income__c);
            body.put('marital_status', mapMaritalStatus(loan.Marital_Status__c));
            body.put('gender', loan.Gender__c);
        } else if (provider == 'AKSHAR') {
            body.put('pan_number', loan.PAN_Number__c);
            body.put('date_of_birth', String.valueOf(loan.Date_Of_Birth__c));
            body.put(
                'address',
                String.join(
                    new List<String>{ loan.flat_no__c, loan.street__c },
                    ', '
                )
            );
            body.put('city', String.valueOf(loan.City__c));
            body.put('state', String.valueOf(loan.State__c));
            body.put('pincode', loan.pincode__c);
            body.put('student_first_name', loan.First_Name__c);
            body.put('student_last_name', loan.First_Name__c);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Endpoint_URL__c);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
            req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }

        String requestPayload = JSON.serialize(body);
        if (method != 'GET') {
            req.setBody(requestPayload);
        }

        System.debug(LoggingLevel.INFO, 'Callout request body: ' + requestPayload);

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Loan Process API',
                requestPayload,
                null,
                'Callout error: ' + e.getMessage(),
                'Failed',
                500
            );
            throw new AuraHandledException('Loan vendor service is unavailable. Please try again later.');
        }

        String responsePayload = res != null ? res.getBody() : null;
        System.debug(
            LoggingLevel.INFO,
            'Callout response status: ' + (res != null ? res.getStatusCode() : null) +
            ', body: ' + responsePayload
        );
        if (res == null || res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            IntegrationLogUtil.insertLog(
                'Loan Process API',
                requestPayload,
                truncateResponse(responsePayload),
                'HTTP ' + (res != null ? res.getStatusCode() : null) + ' ' + (res != null ? res.getStatus() : null),
                'Failed',
                (res != null ? res.getStatusCode() : 500)
            );
            throw new AuraHandledException(buildFriendlyErrorFromPayload(responsePayload));
        }

        ApiResult parsed = parseResponse(responsePayload);
        if (parsed == null || parsed.success != true) {
            String msg = parsed != null ? parsed.message : null;
            IntegrationLogUtil.insertLog(
                'Loan Process API',
                requestPayload,
                truncateResponse(responsePayload),
                'API failure: ' + (msg != null ? msg : 'Unknown error'),
                'Failed',
                (res != null ? res.getStatusCode() : 500)
            );
            throw new AuraHandledException(buildFriendlyErrorFromPayload(msg));
        }

        if (parsed.data != null) {
            loan.miles_loan_code__c = toStringValue(parsed.data.get('miles_loan_code'));
            loan.application_id__c = toStringValue(parsed.data.get('application_id'));
            loan.Loan_status__c = toStringValue(parsed.data.get('loan_status'));
            loan.Redirection_URL__c = toStringValue(parsed.data.get('redirection_url'));
            loan.Loan_Id__c = toStringValue(parsed.data.get('loan_id'));
        }

        IntegrationLogUtil.insertLog(
            'Loan Process API',
            requestPayload,
            truncateResponse(responsePayload),
            'Success',
            'Success',
            (res != null ? res.getStatusCode() : 200)
        );
    }

    private static External_Service_Config__mdt loadConfig() {
        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c
                FROM External_Service_Config__mdt
                WHERE DeveloperName = 'Loan_Process_API'
                LIMIT 1
            ];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Loan Process API',
                null,
                null,
                'Config load error: ' + e.getMessage(),
                'Failed',
                500
            );
            return null;
        }
        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            return null;
        }
        return cfg;
    }

    private static String resolveRecordTypeDeveloperName(Id recordTypeId) {
        if (recordTypeId == null) return null;
        Map<Id, Schema.RecordTypeInfo> rtInfos =
            Loan__c.SObjectType.getDescribe().getRecordTypeInfosById();
        if (rtInfos != null && rtInfos.containsKey(recordTypeId)) {
            return rtInfos.get(recordTypeId).getDeveloperName();
        }
        return null;
    }

    private static ApiResult parseResponse(String payload) {
        if (String.isBlank(payload)) return null;
        Map<String, Object> resp;
        try {
            resp = (Map<String, Object>) JSON.deserializeUntyped(payload);
        } catch (Exception e) {
            return null;
        }
        ApiResult r = new ApiResult();
        if (resp.containsKey('success')) {
            r.success = (resp.get('success') instanceof Boolean) ? (Boolean) resp.get('success') : null;
        }
        r.message = toStringValue(resp.get('message'));
        r.data = (Map<String, Object>) resp.get('data');

        Map<String, Object> result = (Map<String, Object>) resp.get('result');
        if (result != null) {
            Object ok2 = result.get('success');
            if (ok2 instanceof Boolean) r.success = (Boolean) ok2;
            Map<String, Object> data2 = (Map<String, Object>) result.get('data');
            if (data2 != null) r.data = data2;
            if (String.isBlank(r.message)) r.message = toStringValue(result.get('message'));
        }
        return r;
    }

    private static String buildFriendlyErrorFromPayload(String payloadOrMessage) {
        if (String.isBlank(payloadOrMessage)) {
            return 'Unable to create loan with vendor. Please try again later.';
        }
        // If this is JSON, try to extract a message field
        if (payloadOrMessage.trim().startsWith('{')) {
            try {
                Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(payloadOrMessage);
                String msg = toStringValue(resp.get('message'));
                if (!String.isBlank(msg)) return msg;
                Map<String, Object> result = (Map<String, Object>) resp.get('result');
                if (result != null) {
                    String msg2 = toStringValue(result.get('message'));
                    if (!String.isBlank(msg2)) return msg2;
                }
            } catch (Exception e) {
                // fall through
            }
        }
        return payloadOrMessage;
    }

    private static String toStringValue(Object v) {
        return v == null ? null : String.valueOf(v);
    }

    private static String truncateResponse(String payload) {
        if (payload == null) return null;
        return (payload.length() > 3000) ? payload.substring(0, 3000) : payload;
    }

    private static String resolveCandidateUuid(Id candidateId) {
        if (candidateId == null) return null;
        try {
            Lead cand = [SELECT UUID__c FROM Lead WHERE Id = :candidateId LIMIT 1];
            return cand.UUID__c;
        } catch (Exception e) {
            return null;
        }
    }

    private static void validateRequiredFields(Loan__c loan, String provider) {
        List<String> missing = new List<String>();

        // Common required fields for all providers
        addIfMissing(missing, loan.Program_Name__c, 'Program Name');
        addIfMissing(missing, loan.First_Name__c, 'First Name');
        addIfMissing(missing, loan.Email__c, 'Email');
        addIfMissing(missing, loan.Mobile__c, 'Mobile');
        addIfMissing(missing, loan.Amount_Requested__c, 'Amount Requested');
        addIfMissing(missing, loan.Tenure__c, 'Tenure');

        if (provider == 'PROPELLD') {
            // Only common fields required
        } else if (provider == 'AVANSE') {
            // Permanent address required
            addIfMissing(missing, loan.flat_no__c, 'Current Flat No');
            addIfMissing(missing, loan.street__c, 'Current Street');
            addIfMissing(missing, loan.land_mark__c, 'Current Landmark');
            addIfMissing(missing, loan.pincode__c, 'Current Pincode');

            // Permanent address required only if not same as current
            if (loan.Permanent_address_same_as_Current__c != true) {
                addIfMissing(missing, loan.permanent_flat_no__c, 'Permanent Flat No');
                addIfMissing(missing, loan.permanent_street__c, 'Permanent Street');
                addIfMissing(missing, loan.permanent_land_mark__c, 'Permanent Landmark');
                addIfMissing(missing, loan.permanent_pincode__c, 'Permanent Pincode');
            }

            // Applicant details
            addIfMissing(missing, loan.Applying_Loan_For__c, 'Applying Loan For');
            if (loan.Applying_Loan_For__c == 'OTHER') {
                addIfMissing(missing, loan.Relationship_With_Applicant__c, 'Relationship With Applicant');
            }

            // Employment & personal details
            addIfMissing(missing, loan.Earning_Status__c, 'Earning Status');
            if (loan.Earning_Status__c == 'Earning') {
                addIfMissing(missing, loan.Occupation_Type__c, 'Occupation Type');
                addIfMissing(missing, loan.Monthly_Income__c, 'Monthly Income');
            }
            addIfMissing(missing, loan.Marital_Status__c, 'Marital Status');
            addIfMissing(missing, loan.Gender__c, 'Gender');
        } else if (provider == 'AKSHAR') {
            // All Akshar fields mandatory (including common)
            addIfMissing(missing, loan.PAN_Number__c, 'PAN Number');
            addIfMissing(missing, loan.Date_Of_Birth__c, 'Date of Birth');
            addIfMissing(missing, loan.flat_no__c, 'Address Flat No');
            addIfMissing(missing, loan.street__c, 'Address Street');
            addIfMissing(missing, loan.City__c, 'City');
            addIfMissing(missing, loan.State__c, 'State');
            addIfMissing(missing, loan.pincode__c, 'Pincode');
        }

        if (!missing.isEmpty()) {
            throw new AuraHandledException('Please fill required fields: ' + String.join(missing, ', ') + '.');
        }
    }

    private static void addIfMissing(List<String> missing, Object value, String label) {
        if (value == null) {
            missing.add(label);
            return;
        }
        if (value instanceof String && String.isBlank((String) value)) {
            missing.add(label);
        }
    }

    private static void putCurrentAddress(Map<String, Object> body, Loan__c loan) {
        body.put('flat_no', loan.flat_no__c);
        body.put('street', loan.street__c);
        body.put('land_mark', loan.land_mark__c);
        body.put('pincode', loan.pincode__c);
    }

    private static void putPermanentAddress(Map<String, Object> body, Loan__c loan) {
        body.put('permanent_flat_no', loan.permanent_flat_no__c);
        body.put('permanent_street', loan.permanent_street__c);
        body.put('permanent_land_mark', loan.permanent_land_mark__c);
        body.put('permanent_pincode', loan.permanent_pincode__c);
    }

    private static Integer mapTenure(String tenureVal) {
        if (tenureVal == null) return null;
        if (tenureVal.contains('3')) return 3;
        if (tenureVal.contains('6')) return 6;
        return null;
    }

    private static Integer mapEarningStatus(String val) {
        if (val == 'Earning') return 1;
        if (val == 'Not Earning') return 0;
        return null;
    }

    private static Integer mapOccupation(String val) {
        if (val == 'Salaried') return 1;
        if (val == 'Self Employed') return 2;
        return null;
    }

    private static String mapMaritalStatus(String val) {
        if (val == 'Single') return 'S';
        if (val == 'Married') return 'M';
        if (val == 'Divorced') return 'D';
        if (val == 'Other') return 'O';
        return null;
    }
}