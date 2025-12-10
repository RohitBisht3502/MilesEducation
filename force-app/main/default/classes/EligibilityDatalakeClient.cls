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

    public class CalloutResult {
        public Integer statusCode;
        public String body;
        public Boolean success;
        public String message;
    }

    public static String getDownloadUrl(String filePath) {
        if (String.isBlank(filePath)) {
            throw new AuraHandledException('Missing file path for download.');
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        String qp = EncodingUtil.urlEncode(filePath, 'UTF-8');
        req.setEndpoint(BASE_URL + '/getEligibilityDocuments?file_path='+ qp);
        req.setHeader('x-api-key', API_KEY);

        Http http = new Http();
        HTTPResponse res = http.send(req);

        if (res == null) {
            throw new AuraHandledException('No response from datalake download API.');
        }
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException('Download API returned ' + res.getStatusCode() + ': ' + res.getBody());
        }

        DownloadResponse dr = (DownloadResponse) JSON.deserialize(res.getBody(), DownloadResponse.class);
        if (dr == null || String.isBlank(dr.url)) {
            throw new AuraHandledException('Download URL not found in API response.');
        }
        return dr.url;
    }

    public static CalloutResult postEligibilityResponse(EligibilityResponsePayload payload) {
        CalloutResult cr = new CalloutResult();
        cr.success = false;

        if (payload == null || String.isBlank(payload.sf_id)) {
            cr.message = 'Missing sf_id in payload.';
            return cr;
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(BASE_URL + '/eligibilityResponseFromSalesForce');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', API_KEY);
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HTTPResponse res = http.send(req);

        cr.statusCode = (res != null) ? res.getStatusCode() : null;
        cr.body = (res != null) ? res.getBody() : null;

        if (res == null) {
            cr.message = 'No response received.';
            return cr;
        }
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            cr.success = true;
            cr.message = 'ok';
        } else {
            cr.message = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
        }
        return cr;
    }
}