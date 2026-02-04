public without sharing  class Callout_PaymentUpdateApi {

    @future(callout= true)
   
    public static void sendPaymentUpdate(Id purchaseOrderId, Decimal downPayment) {

        if (purchaseOrderId == null || downPayment == null) return;

        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Endpoint_URL__c,
                       Http_Method__c,
                       Api_Key__c,
                       Api_Key_Header__c,
                       Is_Active__c
                FROM External_Service_Config__mdt
                WHERE DeveloperName = 'Payment_Update_API'
                LIMIT 1
            ];
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
        Map<String, Object> payload = new Map<String, Object>{
            'purchaseOrderId' => purchaseOrderId,
            'downPayment'     => downPayment
        };

        // GET vs POST handling
        if (method == 'GET') {
            String endpoint =
                cfg.Endpoint_URL__c +
                '?purchaseOrderId=' + EncodingUtil.urlEncode(String.valueOf(purchaseOrderId), 'UTF-8') +
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
}