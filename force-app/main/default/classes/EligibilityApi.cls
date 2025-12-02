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
            String body = req.requestBody != null ? req.requestBody.toString() : null;
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

            EligibilityFileService.NewQualificationRequest input =
                new EligibilityFileService.NewQualificationRequest();

            input.salesforceId           = raw.sf_id;
            input.qualificationType      = raw.qualification_type;
            input.qualificationTitle     = raw.qualification_title;
            input.qualificationMonthYear = raw.qualification_date;
            input.certificateFiles       = new List<EligibilityFileService.IncomingFile>();
            input.marksheetFiles         = new List<EligibilityFileService.IncomingFile>();

            if (raw.files != null && raw.files.certificates != null) {
                for (FileItem fi : raw.files.certificates) {
                    if (fi == null || String.isBlank(fi.file_path) || String.isBlank(fi.file_UUID)) continue;
                    EligibilityFileService.IncomingFile f = new EligibilityFileService.IncomingFile();
                    f.uuid      = fi.file_UUID;
                    f.path      = fi.file_path;
                    f.format    = fi.file_type;
                    f.fileType  = 'Certificate';
                    input.certificateFiles.add(f);
                }
            }

            if (raw.files != null && raw.files.mark_sheets != null) {
                for (FileItem fi : raw.files.mark_sheets) {
                    if (fi == null || String.isBlank(fi.file_path) || String.isBlank(fi.file_UUID)) continue;
                    EligibilityFileService.IncomingFile f = new EligibilityFileService.IncomingFile();
                    f.uuid      = fi.file_UUID;
                    f.path      = fi.file_path;
                    f.format    = fi.file_type;
                    f.fileType  = 'Marksheet';
                    input.marksheetFiles.add(f);
                }
            }

            EligibilityFileService.ApiResponse svcRes =
                EligibilityFileService.handleNewQualification(input);

            res.success = svcRes.success;
            res.message = svcRes.message;

        } catch (Exception e) {
            System.debug('EligibilityApi.upsertQualification ERROR: ' + e.getMessage());
            res.success = false;
            res.message = 'Error processing request: ' + e.getMessage();
        }
        return res;
    }
}