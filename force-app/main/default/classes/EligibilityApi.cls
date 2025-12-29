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
        RestRequest req = RestContext.request;
        String body = (req != null && req.requestBody != null) ? req.requestBody.toString() : null;

        IntegrationLogService.LogParams logParams = new IntegrationLogService.LogParams();
        logParams.integrationType = 'Inbound files';
        logParams.requestPayload = body;

        try {
            System.debug('EligibilityApi.upsertQualification body: ' + body);

            if (String.isBlank(body)) {
                res.success = false;
                res.message = 'Request body is empty.';
                logParams.status = 'failed';
                logParams.errorMessage = res.message;
                return res;
            }

            RawNewQualificationRequest raw =
                (RawNewQualificationRequest) JSON.deserialize(body, RawNewQualificationRequest.class);

            if (raw == null || String.isBlank(raw.sf_id)) {
                res.success = false;
                res.message = 'Missing sf_id (Lead Id).';
                logParams.status = 'failed';
                logParams.errorMessage = res.message;
                return res;
            }

            // Validate Lead status (must not be "Yet to Initiate")
            Lead targetLead = [
                SELECT GP_Lead_Status__c
                FROM Lead
                WHERE Id = :raw.sf_id
                LIMIT 1
            ];
            if (targetLead != null &&
                targetLead.GP_Lead_Status__c != null &&
                targetLead.GP_Lead_Status__c.equalsIgnoreCase('Yet to Initiate')) {
                res.success = false;
                res.message = 'Candidate eligibility process is yet to be initiated. Please check with the sales SPOC to initiate the document verification process.';
                logParams.status = 'failed';
                logParams.errorMessage = res.message;
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
                    logParams.status = 'failed';
                    logParams.errorMessage = res.message;
                    return res;
                }
            }

            res.success = true;
            res.message = 'Qualification files synced successfully.';
            logParams.status = 'Success';
            logParams.responsePayload = JSON.serialize(res);

        } catch (Exception e) {
            System.debug('EligibilityApi.upsertQualification ERROR: ' + e.getMessage());
            res.success = false;
            res.message = 'Error processing request: ' + e.getMessage();
            logParams.status = 'failed';
            logParams.errorMessage = e.getMessage();
            logParams.responsePayload = JSON.serialize(res);
        } finally {
            IntegrationLogService.log(logParams);
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