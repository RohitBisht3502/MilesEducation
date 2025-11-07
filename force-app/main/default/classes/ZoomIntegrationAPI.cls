@RestResource(urlMapping='/zoom/*')
global with sharing class ZoomIntegrationAPI {

    @HttpPost
    global static void handleZoomRequest() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        // Get path, e.g. /services/apexrest/zoom/generateToken
        String path = req.requestURI != null ? req.requestURI.toLowerCase() : '';

        try {
            if (path.contains('generatetoken')) {
                generateZoomToken(req, res);
            } else if (path.contains('registerwebinar')) {
                registerForWebinar(req, res);
            } else {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf('Invalid Zoom API endpoint.');
            }
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(
                JSON.serializePretty(new Map<String, Object>{ 'error' => e.getMessage() })
            );
        }
    }

    // -------- Generate Token --------
    private static void generateZoomToken(RestRequest req, RestResponse res) {
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
        String clientId = (String) input.get('client_id');
        String clientSecret = (String) input.get('client_secret');
        String accountId = (String) input.get('account_id');

        String basicAuth = EncodingUtil.base64Encode(Blob.valueOf(clientId + ':' + clientSecret));

        Http http = new Http();
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('https://zoom.us/oauth/token');
        httpReq.setMethod('POST');
        httpReq.setHeader('Authorization', 'Basic ' + basicAuth);
        httpReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        httpReq.setBody('grant_type=account_credentials&account_id=' + accountId);

        HttpResponse httpRes = http.send(httpReq);
        res.statusCode = httpRes.getStatusCode();
        res.responseBody = httpRes.getBodyAsBlob();
    }

    // -------- Register Webinar --------
    private static void registerForWebinar(RestRequest req, RestResponse res) {
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
        String accessToken = (String) input.get('access_token');
        String webinarId = (String) input.get('webinarId');
        Map<String, Object> registrant = (Map<String, Object>) input.get('registrant');

        Http http = new Http();
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('https://api.zoom.us/v2/webinars/' + webinarId + '/registrants');
        httpReq.setMethod('POST');
        httpReq.setHeader('Authorization', 'Bearer ' + accessToken);
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setBody(JSON.serialize(registrant));

        HttpResponse httpRes = http.send(httpReq);
        res.statusCode = httpRes.getStatusCode();
        res.responseBody = httpRes.getBodyAsBlob();
    }
}