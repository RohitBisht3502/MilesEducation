/*
    Author       : MANJIT KUNDU
    Description  : 
*/
@RestResource(urlMapping='/eligibility/*')
global without sharing class EligibilityApi {

    global class ApiResponse {
        public Boolean success;
        public String message;
    }

    global class FileItem {
        public String file_type;
        public String file_path;
        public String file_UUID;
        public String file_name;
    }

    global class FilesWrapper {
        public List<FileItem> certificates;
        public List<FileItem> mark_sheets;
    }

    global class RawNewQualificationRequest {
        public String sf_id;
        public String qualification_type;
        public String qualification_date;
        public String qualification_title;
        public FilesWrapper files;
    }

    @HttpPost
    global static ApiResponse upsertQualification() {
        ApiResponse res = new ApiResponse();
        try {
            RestRequest req = RestContext.request;
            String body = (req.requestBody != null) ? req.requestBody.toString() : null;
            System.debug('EligibilityApi.upsertQualification body: ' + body);

            if (String.isBlank(body)) {
                res.success = false;
                res.message = 'Request body is empty.';
                return res;
            }

            RawNewQualificationRequest raw =
                (RawNewQualificationRequest) JSON.deserialize(body, RawNewQualificationRequest.class);

            if (raw == null || String.isBlank(raw.sf_id)) {
                res.success = false;
                res.message = 'Missing sf_id (Lead Id).';
                return res;
            }

            // Group incoming files by parsed qualification (type + title) from file_path
            Map<String, EligibilityFileService.NewQualificationRequest> grouped = new Map<String, EligibilityFileService.NewQualificationRequest>();

            if (raw.files != null) {
                processIncomingFiles(raw.sf_id, raw.files.certificates, 'Certificate', grouped);
                processIncomingFiles(raw.sf_id, raw.files.mark_sheets, 'Marksheet', grouped);
            }

            for (EligibilityFileService.NewQualificationRequest nq : grouped.values()) {
                EligibilityFileService.SimpleResponse svcRes =
                    EligibilityFileService.handleNewQualification(JSON.serialize(nq));

                if (!svcRes.success) {
                    res.success = false;
                    res.message = svcRes.message;
                    return res;
                }
            }

            res.success = true;
            res.message = 'Qualification files synced successfully.';

        } catch (Exception e) {
            System.debug('EligibilityApi.upsertQualification ERROR: ' + e.getMessage());
            res.success = false;
            res.message = 'Error processing request: ' + e.getMessage();
        }
        return res;
    }

    private static void processIncomingFiles(
        String salesforceId,
        List<FileItem> items,
        String logicalType,
        Map<String, EligibilityFileService.NewQualificationRequest> grouped
    ) {
        if (items == null || items.isEmpty()) return;

        for (FileItem fi : items) {
            if (fi == null || String.isBlank(fi.file_path) || String.isBlank(fi.file_UUID)) continue;

            EligibilityPathParser.ParsedPath parsed = EligibilityPathParser.parse(fi.file_path);
            if (parsed == null || String.isBlank(parsed.qualificationType) || String.isBlank(parsed.qualificationTitle)) {
                continue;
            }

            String key = parsed.qualificationType + '||' + parsed.qualificationTitle;
            EligibilityFileService.NewQualificationRequest nq = grouped.get(key);
            if (nq == null) {
                nq = new EligibilityFileService.NewQualificationRequest();
                nq.salesforceId = salesforceId;
                nq.qualificationType = parsed.qualificationType;
                nq.qualificationTitle = parsed.qualificationTitle;
                nq.qualificationMonthYear = null;
                nq.certificateFiles = new List<EligibilityFileService.IncomingFile>();
                nq.marksheetFiles = new List<EligibilityFileService.IncomingFile>();
                grouped.put(key, nq);
            }

            EligibilityFileService.IncomingFile f = new EligibilityFileService.IncomingFile();
            f.uuid = fi.file_UUID;
            f.path = fi.file_path;
            f.format = fi.file_type;
            f.fileType = logicalType;
            f.fileName = !String.isBlank(fi.file_name)
                ? fi.file_name
                : (parsed.fileName != null ? parsed.fileName : null);

            if (logicalType == 'Certificate') {
                nq.certificateFiles.add(f);
            } else {
                nq.marksheetFiles.add(f);
            }
        }
    }
}