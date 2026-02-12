public without sharing  class Callout_PaymentUpdateApi {

    @future(callout= true)
   
    public static void sendPaymentUpdate(String purchaseOrderId, Decimal downPayment) {

        if (String.isBlank(purchaseOrderId) || downPayment == null) return;

        Integer purchaseId;
        try {
            purchaseId = Integer.valueOf(purchaseOrderId);
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                null,
                null,
                'Invalid purchaseId (must be integer): ' + e.getMessage(),
                'Failed',
                null
            );
            return;
        }

        External_Service_Config__mdt cfg;
        try {
            cfg = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Payment_Update_API' LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                null,
                null,
                'Metadata load error: ' + e.getMessage(),
                'Failed',
                null
            );
            return;
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                null,
                null,
                'Inactive or missing endpoint',
                'Failed',
                null
            );
            return;
        }

        String method = String.isBlank(cfg.Http_Method__c)
            ? 'POST'
            : cfg.Http_Method__c.trim().toUpperCase();

        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');

        if (!String.isBlank(cfg.Api_Key__c) &&
            !String.isBlank(cfg.Api_Key_Header__c)) {
            req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }

        // Payload
        PaymentUpdatePayload payload = new PaymentUpdatePayload(
            purchaseId,
            downPayment,
            'MPE226'
        );

        // GET vs POST handling
        if (method == 'GET') {
            String endpoint =
                cfg.Endpoint_URL__c +
                '?purchaseId=' + EncodingUtil.urlEncode(String.valueOf(purchaseId), 'UTF-8') +
                '&downPayment=' + EncodingUtil.urlEncode(String.valueOf(downPayment), 'UTF-8');

            req.setEndpoint(endpoint);
        } else {
            req.setEndpoint(cfg.Endpoint_URL__c);
            req.setBody(JSON.serialize(payload));
        }

        Http http = new Http();

        try {
            HttpResponse res = http.send(req);
            Integer statusCode = res.getStatusCode();
            String resBody = res.getBody();
            String trimmedBody =
                (resBody != null && resBody.length() > 3000)
                ? resBody.substring(0, 3000)
                : resBody;

            if (statusCode >= 200 && statusCode < 300) {
                IntegrationLogUtil.insertLog(
                    'Payment Update API',
                    JSON.serialize(payload),
                    trimmedBody,
                    'Success',
                    'Success',
                    statusCode
                );
            } else {
                IntegrationLogUtil.insertLog(
                    'Payment Update API',
                    JSON.serialize(payload),
                    trimmedBody,
                    'Non-success response',
                    'Failed',
                    statusCode
                );
            }
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                JSON.serialize(payload),
                null,
                'Callout error: ' + e.getMessage(),
                'Failed',
                null
            );
        }
    }

    public static PaymentUpdateResponse sendPaymentUpdateSync(String purchaseOrderId, Decimal downPayment) {

        if (String.isBlank(purchaseOrderId) || downPayment == null) return null;

        Integer purchaseId;
        try {
            purchaseId = Integer.valueOf(purchaseOrderId);
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                null,
                null,
                'Invalid purchaseId (must be integer): ' + e.getMessage(),
                'Failed',
                null
            );
            return null;
        }

        External_Service_Config__mdt cfg;
        try {
            cfg = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'Payment_Update_API' LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                null,
                null,
                'Metadata load error: ' + e.getMessage(),
                'Failed',
                null
            );
            return null;
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                null,
                null,
                'Inactive or missing endpoint',
                'Failed',
                null
            );
            return null;
        }

        String method = String.isBlank(cfg.Http_Method__c)
            ? 'POST'
            : cfg.Http_Method__c.trim().toUpperCase();

        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');

        if (!String.isBlank(cfg.Api_Key__c) &&
            !String.isBlank(cfg.Api_Key_Header__c)) {
            req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }

        PaymentUpdatePayload payload = new PaymentUpdatePayload(
            purchaseId,
            downPayment,
            'MPE226'
        );

        if (method == 'GET') {
            String endpoint =
                cfg.Endpoint_URL__c +
                '?purchaseId=' + EncodingUtil.urlEncode(String.valueOf(purchaseId), 'UTF-8') +
                '&downPayment=' + EncodingUtil.urlEncode(String.valueOf(downPayment), 'UTF-8');

            req.setEndpoint(endpoint);
        } else {
            req.setEndpoint(cfg.Endpoint_URL__c);
            req.setBody(JSON.serialize(payload));
        }

        Http http = new Http();

        try {
            HttpResponse res = http.send(req);
            Integer statusCode = res.getStatusCode();
            String resBody = res.getBody();
            String trimmedBody =
                (resBody != null && resBody.length() > 3000)
                ? resBody.substring(0, 3000)
                : resBody;

            PaymentUpdateResponse parsed = null;
            if (!String.isBlank(resBody)) {
                try {
                    parsed = (PaymentUpdateResponse) JSON.deserialize(resBody, PaymentUpdateResponse.class);
                } catch (Exception ex) {
                    IntegrationLogUtil.insertLog(
                        'Payment Update API',
                        JSON.serialize(payload),
                        trimmedBody,
                        'Response parse error: ' + ex.getMessage(),
                        'Failed',
                        statusCode
                    );
                }
            }

            if (statusCode >= 200 && statusCode < 300) {
                IntegrationLogUtil.insertLog(
                    'Payment Update API',
                    JSON.serialize(payload),
                    trimmedBody,
                    'Success',
                    'Success',
                    statusCode
                );
            } else {
                IntegrationLogUtil.insertLog(
                    'Payment Update API',
                    JSON.serialize(payload),
                    trimmedBody,
                    'Non-success response',
                    'Failed',
                    statusCode
                );
            }

            return parsed;
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Payment Update API',
                JSON.serialize(payload),
                null,
                'Callout error: ' + e.getMessage(),
                'Failed',
                null
            );
            return null;
        }
    }

    public class PaymentUpdatePayload {
        public Integer purchaseId;
        public Decimal amount;
        public String created_by;

        public PaymentUpdatePayload(Integer purchaseId, Decimal amount, String created_by) {
            this.purchaseId = purchaseId;
            this.amount = amount;
            this.created_by = created_by;
        }
    }

    public class PaymentUpdateResponse {
        public Boolean status;
        public String path;
        public Integer statusCode;
        public PaymentUpdateResult result;
    }

    public class PaymentUpdateResult {
        public Integer created_by;
        public Integer business_vertical_id;
        public String uuid;
        public String link;
        public Integer purchase_id;
        public Integer lead_id;
        public Decimal amount;
        public Integer updated_by;
        public Integer id;
        public Boolean status;
        public String created_at;
        public String updated_at;
        public String link_status;
        public Boolean is_down_payment;
    }
}