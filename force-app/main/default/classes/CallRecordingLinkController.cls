// Simple controller to generate a presigned URL for call recordings.
public without sharing class CallRecordingLinkController {
    private static final String BASE_URL = 'https://hn19ywvvng.execute-api.ap-south-1.amazonaws.com/Miles360';
    private static final String API_KEY  = 'n7yno1N32NaXgZJFLbzf137wCHFf2UsM40j7gSgW';

    public class DownloadResponse {
        public String url;
    }

    @AuraEnabled(cacheable=false)
    public static String getDownloadUrlForLwc(String filePath) {
        if (String.isBlank(filePath)) {
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        String qp = EncodingUtil.urlEncode(filePath, 'UTF-8');
        req.setEndpoint(BASE_URL + '/getPresignedUrlForFileDownload?file_path=' + qp + '&type=call_recording');
        req.setHeader('x-api-key', API_KEY);

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res == null || res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            return null;
        }

        DownloadResponse dr = (DownloadResponse) JSON.deserialize(res.getBody(), DownloadResponse.class);
        return dr == null ? null : dr.url;
    }
}