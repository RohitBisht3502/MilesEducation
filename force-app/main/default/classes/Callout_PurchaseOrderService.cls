/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : Callout_PurchaseOrderService
 * Author          : Rohit Singh Bisht
 * Created Date    : Jan 9, 2026
 */

public without sharing class Callout_PurchaseOrderService {

    public class Request{
        public String source;
        public String sf_id;
        public String sf_lead_id;
        public String uuid;
        public List<RequestItem> purchase_items;
        public Decimal down_payment;
    }

    public class RequestItem{
        public String program;
        public List<String> skus;
        public Decimal actual_price;
        public Decimal agreed_price;
        public Decimal discount;
        public String loan_id;
        public Boolean has_training;
        public Boolean has_study_material;
    }

    public class Response{
        public String purchase_id;
    }

    public static String createPurchase(Request req){

        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c
                FROM External_Service_Config__mdt
                WHERE DeveloperName = 'Purcahse_Order_Service'
                LIMIT 1];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                null,
                'Config load error: ' + e.getMessage(),
                'Failed',
                500
            );
            throw new AuraHandledException('Failed to load external service config: ' + e.getMessage());
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                null,
                'Config inactive or missing Endpoint_URL__c',
                'Failed',
                500
            );
            throw new AuraHandledException('Service is not configured or inactive.');
        }

        if (req == null) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                null,
                'Request is null',
                'Failed',
                400
            );
            throw new AuraHandledException('Request is empty.');
        }

        String methodName = String.isBlank(cfg.Http_Method__c) ? 'POST' : cfg.Http_Method__c.trim().toUpperCase();
        if (methodName != 'POST') methodName = 'POST';

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(cfg.Endpoint_URL__c);
        httpReq.setMethod(methodName);
        httpReq.setHeader('Content-Type', 'application/json');

        if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
            httpReq.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }

        String requestBody = JSON.serialize(req);
        httpReq.setBody(requestBody);

        Http http = new Http();
        HttpResponse httpRes;

        try {
            httpRes = http.send(httpReq);
        } catch (Exception e) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                null,
                'Callout error: ' + e.getMessage(),
                'Failed',
                500
            );
            throw new AuraHandledException('Callout failed: ' + e.getMessage());
        }

        Integer sc = httpRes.getStatusCode();
        String resBody = httpRes.getBody();

        if (sc < 200 || sc >= 300 || String.isBlank(resBody)) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                (resBody != null && resBody.length() > 3000 ? resBody.substring(0, 3000) : resBody),
                'HTTP ' + sc + ' ' + httpRes.getStatus(),
                'Failed',
                sc
            );
            throw new AuraHandledException('External API failed (HTTP ' + sc + '): ' + (resBody == null ? '' : resBody));
        }

        Response resp;
        try {
            resp = (Response) JSON.deserialize(resBody, Response.class);
        } catch (Exception pe) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                (resBody != null && resBody.length() > 3000 ? resBody.substring(0, 3000) : resBody),
                'Response parse error: ' + pe.getMessage(),
                'Failed',
                500
            );
            throw new AuraHandledException('Invalid response from external service.');
        }

        if (resp == null || String.isBlank(resp.purchase_id)) {
            IntegrationLogUtil.insertLog(
                'Purchase Order Service',
                null,
                (resBody != null && resBody.length() > 3000 ? resBody.substring(0, 3000) : resBody),
                'purchase_id missing in response',
                'Failed',
                500
            );
            throw new AuraHandledException('External service did not return purchase_id.');
        }

        IntegrationLogUtil.insertLog(
            'Purchase Order Service',
            null,
            (resBody != null && resBody.length() > 3000 ? resBody.substring(0, 3000) : resBody),
            'Success | purchase_id=' + resp.purchase_id,
            'Success',
            sc
        );

        return resp.purchase_id;
    }

    // public static String createPurchase(){
    //     throw new AuraHandledException('Use createPurchase(Request req) method with payload.');
    // }
}