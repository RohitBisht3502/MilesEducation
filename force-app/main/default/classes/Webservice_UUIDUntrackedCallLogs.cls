public with sharing class Webservice_UUIDUntrackedCallLogs {

    private static final String ENDPOINT = 'https://hn19ywvvng.execute-api.ap-south-1.amazonaws.com/Miles360/mf-sf-untrack-to-track-recording';
    private static final String API_KEY  = 'n7yno1N32NaXgZJFLbzf137wCHFf2UsM40j7gSgW';

    @future(callout=true)
    public static void sendUntrackedCallLogs(String milesUUID, List<String> callIds) {

        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('miles_uuid', milesUUID);
        requestBody.put('callIds', callIds);

        String requestJSON = JSON.serialize(requestBody);

        System.debug('UUID Untracked Call API - Request ==> ' + requestJSON);

        Http http = new Http();
        HttpRequest req = new HttpRequest();

        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', API_KEY);
        req.setBody(requestJSON);
        req.setTimeout(60000);

        try {

            HttpResponse res = http.send(req);

            Integer statusCode = res.getStatusCode();
            String responseBody = res.getBody();

            System.debug('UUID Untracked Call API - Status Code ==> ' + statusCode);
            System.debug('UUID Untracked Call API - Response ==> ' + responseBody);

            String responseTrimmed = (responseBody != null && responseBody.length() > 3000)
                ? responseBody.substring(0, 3000)
                : responseBody;

            if(statusCode == 200){

                IntegrationLogUtil.insertLog(
                    'UUID Untracked Call Logs API',
                    requestJSON,
                    responseTrimmed,
                    'Recording successfully moved from untracked to tracked',
                    'Success',
                    statusCode
                );

            } else {

                IntegrationLogUtil.insertLog(
                    'UUID Untracked Call Logs API',
                    requestJSON,
                    responseTrimmed,
                    'API returned non-success status',
                    'Failed',
                    statusCode
                );
            }

        } catch(Exception ex){

            System.debug('UUID Untracked Call API - Exception ==> ' + ex.getMessage());

            IntegrationLogUtil.insertLog(
                'UUID Untracked Call Logs API',
                requestJSON,
                null,
                'Exception during callout: ' + ex.getMessage(),
                'Failed',
                500
            );
        }
    }
}