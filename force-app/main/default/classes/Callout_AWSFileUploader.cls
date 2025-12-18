/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class Callout_AWSFileUploader {
    @AuraEnabled(cacheable=false)
    public static String getPresignedUrl(String fileName, String uuid, String contentType) {
        if (String.isBlank(fileName)) throw new AuraHandledException('fileName is required.');
        if (String.isBlank(uuid)) throw new AuraHandledException('uuid is required.');
        if (String.isBlank(contentType)) contentType = 'application/octet-stream';
        
        External_Service_Config__mdt cfg;
        try {
            cfg = [
                SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c FROM External_Service_Config__mdt WHERE DeveloperName = 'AWS_File_Uploader' LIMIT 1 ];
        } catch (Exception e) {
            IntegrationLogUtil.insertLog('AWS File Uploader', null, null, 'Config load error: ' + e.getMessage(), 'Failed', null);
            throw new AuraHandledException('Failed to load external service config: ' + e.getMessage());
        }
        
        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c)) {
            IntegrationLogUtil.insertLog('AWS File Uploader', null, null, 'Config inactive or missing Endpoint_URL__c', 'Failed', null);
            throw new AuraHandledException('Service is not configured or inactive.');
        }
        
        String method = String.isBlank(cfg.Http_Method__c) ? 'GET' : cfg.Http_Method__c.trim().toUpperCase();
        if (method != 'GET') method = 'GET';
        
        String endpoint = cfg.Endpoint_URL__c;
        String urlWithParam = endpoint + (endpoint.contains('?') ? '&' : '?') + 'file_name=' + EncodingUtil.urlEncode(fileName, 'UTF-8') + '&uuid=' + EncodingUtil.urlEncode(uuid, 'UTF-8') + '&content_type=' + EncodingUtil.urlEncode(contentType, 'UTF-8');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(urlWithParam);
        req.setMethod(method);
        if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) {
            req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);
        }
        
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            IntegrationLogUtil.insertLog('AWS File Uploader', null, null, 'Callout error: ' + e.getMessage(), 'Failed', null);
            throw new AuraHandledException('Callout failed: ' + e.getMessage());
        }
        
        Integer code = res.getStatusCode();
        String body = res.getBody();
        
        if (code != 200 || String.isBlank(body)) {
            IntegrationLogUtil.insertLog('AWS File Uploader', null, body, 'Non-200 or empty body', 'Failed', code);
            throw new AuraHandledException('Upload presign API returned error. Status: ' + code);
        }
        
        Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(body);
        String url = (untyped == null) ? null : (String) untyped.get('url');
        if (String.isBlank(url)) {
            IntegrationLogUtil.insertLog('AWS File Uploader', null, body, 'Missing url in response', 'Failed', code);
            throw new AuraHandledException('Invalid pre-signed URL response.');
        }
        
        IntegrationLogUtil.insertLog('AWS File Uploader',null,(body != null && body.length() > 3000 ? body.substring(0, 3000) : body),'Success','Success',200 );
        return url;
    }
}