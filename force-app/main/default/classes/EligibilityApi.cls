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

            Object rawObj = JSON.deserializeUntyped(body);
            if (!(rawObj instanceof Map<String, Object>)) {
                res.success = false;
                res.message = 'Invalid payload.';
                logParams.status = 'failed';
                logParams.errorMessage = res.message;
                return res;
            }

            Map<String, Object> raw = (Map<String, Object>) rawObj;
            String sfId = (String) raw.get('sf_id');
            String qualificationTitle = (String) raw.get('qualification_title');

            if (String.isBlank(sfId)) {
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
                WHERE Id = :sfId
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
            Map<String, List<EligibilityFileService.IncomingFile>> flatGrouped = new Map<String, List<EligibilityFileService.IncomingFile>>();

            if (raw.containsKey('files')) {
                Object filesObj = raw.get('files');
                if (filesObj instanceof Map<String, Object>) {
                    Map<String, Object> filesMap = (Map<String, Object>) filesObj;
                    processIncomingFiles(
                        sfId,
                        parseFileItems(filesMap.get('certificates')),
                        'Certificate',
                        grouped,
                        flatGrouped,
                        qualificationTitle
                    );
                    processIncomingFiles(
                        sfId,
                        parseFileItems(filesMap.get('mark_sheets')),
                        'Marksheet',
                        grouped,
                        flatGrouped,
                        qualificationTitle
                    );
                } else if (filesObj instanceof List<Object>) {
                    processIncomingFiles(
                        sfId,
                        parseFileItems(filesObj),
                        null,
                        grouped,
                        flatGrouped,
                        qualificationTitle
                    );
                }
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

            for (String flatKey : flatGrouped.keySet()) {
                EligibilityFileService.SimpleResponse svcRes =
                    EligibilityFileService.handleMainFolderFiles(sfId, flatKey, flatGrouped.get(flatKey));

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
        Map<String, EligibilityFileService.NewQualificationRequest> grouped,
        Map<String, List<EligibilityFileService.IncomingFile>> flatGrouped,
        String fallbackQualificationTitle
    ) {
        if (items == null || items.isEmpty()) return;

        for (FileItem fi : items) {
            if (fi == null || String.isBlank(fi.file_path) || String.isBlank(fi.file_UUID)) continue;

            EligibilityPathParser.ParsedPath parsed = EligibilityPathParser.parse(fi.file_path);
            String flatKey = (parsed != null && parsed.isFlat == true)
                ? parsed.flatFolderKey
                : null;
            Boolean hasQualification = parsed != null
                && String.isNotBlank(parsed.qualificationType)
                && String.isNotBlank(parsed.qualificationTitle);
            if (String.isBlank(flatKey) && !hasQualification && !String.isBlank(fallbackQualificationTitle)) {
                flatKey = EligibilityPathParser.normalizeFlatFolderKey(fallbackQualificationTitle);
            }

            if (!String.isBlank(flatKey)) {
                if (!flatGrouped.containsKey(flatKey)) {
                    flatGrouped.put(flatKey, new List<EligibilityFileService.IncomingFile>());
                }
                EligibilityFileService.IncomingFile f = new EligibilityFileService.IncomingFile();
                f.uuid = fi.file_UUID;
                f.path = fi.file_path;
                f.format = fi.file_type;
                f.fileType = logicalType;
                f.fileName = !String.isBlank(fi.file_name)
                    ? fi.file_name
                    : (parsed != null ? parsed.fileName : null);
                flatGrouped.get(flatKey).add(f);
                continue;
            }

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

    private static List<FileItem> parseFileItems(Object rawItems) {
        List<FileItem> items = new List<FileItem>();
        if (rawItems == null) return items;
        if (!(rawItems instanceof List<Object>)) return items;

        for (Object o : (List<Object>) rawItems) {
            if (!(o instanceof Map<String, Object>)) continue;
            Map<String, Object> m = (Map<String, Object>) o;
            FileItem fi = new FileItem();
            fi.file_type = (String) m.get('file_type');
            fi.file_path = (String) m.get('file_path');
            fi.file_UUID = (String) m.get('file_UUID');
            fi.file_name = (String) m.get('file_name');
            items.add(fi);
        }
        return items;
    }
}