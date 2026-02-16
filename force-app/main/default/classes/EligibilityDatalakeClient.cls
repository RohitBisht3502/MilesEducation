// Handles callouts to the Miles360 datalake APIs.
public without sharing class EligibilityDatalakeClient {

    // TODO: move API key to a protected custom setting/Named Credential.
    private static final String BASE_URL = 'https://1c8fjh4ddg.execute-api.ap-south-1.amazonaws.com/Miles360';
    private static final String API_KEY  = 'n7yno1N32NaXgZJFLbzf137wCHFf2UsM40j7gSgW';

    public class DownloadResponse {
        public String url;
    }

    public class FilePayload {
        public String file_type;
        public String file_path;
        public String file_UUID;
        public String file_comment;
        public String file_status;
    }

    public class FilesPayload {
        public List<FilePayload> certificates;
        public List<FilePayload> mark_sheets;
    }

    public class EligibilityResponsePayload {
        public String sf_id;
        public String qualification_title;
        public String qualification_comment;
        public String qualification_status;
        public FilesPayload files;
    }

    public class FlatEligibilityResponsePayload {
        public String sf_id;
        public String qualification_title;
        public String qualification_comment;
        public String qualification_status;
        public List<FilePayload> files;
    }

    public class CalloutResult {
        public Integer statusCode;
        public String body;
        public Boolean success;
        public String message;
    }

    public static String getDownloadUrl(String filePath) {
        if (String.isBlank(filePath)) {
            return null;
        }

        IntegrationLogService.LogParams logParams = new IntegrationLogService.LogParams();
        logParams.integrationType = 'File Visibility';
        logParams.requestPayload = '{"file_path":"' + filePath + '"}';
        logParams.status = 'failed';

        HTTPResponse res = null;
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            String qp = EncodingUtil.urlEncode(filePath, 'UTF-8');
            req.setEndpoint(BASE_URL + '/getPresignedUrlForFileDownload?file_path='+ qp);
            req.setHeader('x-api-key', API_KEY);

            Http http = new Http();
            res = http.send(req);

            if (res == null) {
                logParams.errorMessage = 'No response from datalake download API.';
                logParams.responsePayload = null;
                logParams.statusCode = null;
                return null;
            }
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                logParams.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
                logParams.responsePayload = res.getBody();
                logParams.statusCode = res.getStatusCode();
                return null;
            }

            DownloadResponse dr = (DownloadResponse) JSON.deserialize(res.getBody(), DownloadResponse.class);
            if (dr == null || String.isBlank(dr.url)) {
                logParams.errorMessage = 'Download URL not found in API response.';
                logParams.responsePayload = res.getBody();
                logParams.statusCode = res.getStatusCode();
                return null;
            }

            logParams.status = 'Success';
            logParams.responsePayload = res.getBody();
            logParams.statusCode = res.getStatusCode();
            return dr.url;
        } catch (Exception e) {
            logParams.status = 'failed';
            logParams.errorMessage = e.getMessage();
            logParams.responsePayload = (res != null) ? res.getBody() : null;
            logParams.statusCode = (res != null) ? res.getStatusCode() : null;
            return null;
        } finally {
            IntegrationLogService.log(logParams);
        }
    }

    public static CalloutResult postEligibilityResponse(EligibilityResponsePayload payload) {
        CalloutResult cr = new CalloutResult();
        cr.success = false;

        if (payload == null || String.isBlank(payload.sf_id)) {
            cr.message = 'Missing sf_id in payload.';
            return cr;
        }

        String requestBody = JSON.serialize(payload);
        return postEligibilityResponseInternal(requestBody, cr);
    }

    public static CalloutResult postEligibilityResponseFlat(FlatEligibilityResponsePayload payload) {
        CalloutResult cr = new CalloutResult();
        cr.success = false;

        if (payload == null || String.isBlank(payload.sf_id)) {
            cr.message = 'Missing sf_id in payload.';
            return cr;
        }

        String requestBody = JSON.serialize(payload);
        return postEligibilityResponseInternal(requestBody, cr);
    }

    private static CalloutResult postEligibilityResponseInternal(String requestBody, CalloutResult cr) {
        IntegrationLogService.LogParams logParams = new IntegrationLogService.LogParams();
        logParams.integrationType = 'Outbound status file';
        logParams.requestPayload = requestBody;

        HTTPResponse res = null;
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint(BASE_URL + '/eligibilityResponseFromSalesForce');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', API_KEY);
            req.setBody(requestBody);

            Http http = new Http();
            res = http.send(req);

            cr.statusCode = (res != null) ? res.getStatusCode() : null;
            cr.body = (res != null) ? res.getBody() : null;

            if (res == null) {
                cr.message = 'No response received.';
            } else if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                cr.success = true;
                cr.message = 'ok';
            } else {
                cr.message = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }

            logParams.status = cr.success ? 'Success' : 'failed';
            logParams.responsePayload = (res != null) ? res.getBody() : null;
            logParams.statusCode = (res != null) ? res.getStatusCode() : null;
            logParams.errorMessage = cr.success ? null : cr.message;
            return cr;
        } catch (Exception e) {
            cr.message = e.getMessage();
            logParams.status = 'failed';
            logParams.errorMessage = e.getMessage();
            logParams.responsePayload = (res != null) ? res.getBody() : null;
            logParams.statusCode = (res != null) ? res.getStatusCode() : null;
            return cr;
        } finally {
            IntegrationLogService.log(logParams);
        }
    }
}