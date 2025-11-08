public without sharing class ZoomIntegrationService {

    // ====== ZOOM CONFIGURATION ======
    private static final String TOKEN_URL   = 'https://zoom.us/oauth/token';
    private static final String REGISTER_URL = 'https://api.zoom.us/v2/webinars/';
    private static final String WEBINAR_ID   = '92080917918'; // for now manual

    private static final String CLIENT_ID     = 'VR_eUey6TBaTGU7hRx01jA';
    private static final String CLIENT_SECRET = 'szw5yQDVHOIH3DmBniKBmHFX7H2j9ekT';
    private static final String ACCOUNT_ID    = 'zvrNCCaRTca0xHc7r9JEEA';

    // ====== STEP 1: Generate Zoom Access Token (no DML; append logs only) ======
    public static String generateZoomAccessToken(List<Integration_Log__c> logs) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_URL);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(CLIENT_ID + ':' + CLIENT_SECRET)));
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=account_credentials&account_id=' + ACCOUNT_ID);

        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception ex) {
            logs.add(IntegrationLogUtil.buildLog('Zoom Token API Call',req.getBody(),null,ex.getMessage(),'FAILED',null));
            throw ex;
        }

        System.debug('🔑 [ZoomIntegrationService] Token API Response: ' + res.getBody());

        logs.add(IntegrationLogUtil.buildLog('Zoom Token Generation', req.getBody(), res.getBody(), null, res.getStatus(), res.getStatusCode() ));

        if (res.getStatusCode() != 200) {
            throw new CalloutException('Zoom Token Generation Failed: ' + res.getBody());
        }

        Map<String, Object> tokenData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String accessToken = (String) tokenData.get('access_token');
        System.debug('✅ [ZoomIntegrationService] Access Token: ' + accessToken);
        return accessToken;
    }

    // ====== STEP 2: Register Lead for Webinar (no DML; append logs only) ======
    public static String registerLeadForWebinar(Lead ld, String accessToken, List<Integration_Log__c> logs) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(REGISTER_URL + WEBINAR_ID + '/registrants');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');

        Map<String, Object> registrant = new Map<String, Object>{
            'first_name' => ld.FirstName,
            'last_name'  => ld.LastName,
            'email'      => ld.Email,
            'phone'      => ld.Phone,
            'city'       => ld.City__c
        };

        String payload = JSON.serialize(registrant);
        System.debug('🧾 Webinar Registration Payload: ' + JSON.serializePretty(registrant));
        req.setBody(payload);

        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception ex) {
            logs.add(IntegrationLogUtil.buildLog('Zoom Webinar Registration Call', payload, null, ex.getMessage(), 'FAILED',null ));
            throw ex;
        }

        System.debug('📩 [ZoomIntegrationService] Registration Response: ' + res.getBody());

        logs.add(IntegrationLogUtil.buildLog( 'Zoom Webinar Registration', payload, res.getBody(), null, res.getStatus(), res.getStatusCode() ));

        if (res.getStatusCode() != 201 && res.getStatusCode() != 200) {
            throw new CalloutException('Zoom Webinar Registration Failed: ' + res.getBody());
        }

        return res.getBody();
    }
}