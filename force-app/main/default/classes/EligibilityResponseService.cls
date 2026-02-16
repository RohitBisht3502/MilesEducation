// Builds and sends eligibility status updates to the datalake.
public without sharing class EligibilityResponseService {

    @future(callout=true)
    public static void sendForFile(Id fileId) {
        if (fileId == null) return;

        Eligibility_File__c file = [
            SELECT Id, Candidate__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                   Status__c, Comment__c, Name, File_Type__c
            FROM Eligibility_File__c
            WHERE Id = :fileId
            LIMIT 1
        ];

        if (file.Candidate__c == null || file.Folder__c == null) return;

        // Get category + degree folders
        Eligibility_Folder__c fileFolder = [
            SELECT Id, Name, Folder_Type__c, Parent_Folder__c, Qualification_Type__c, Degree_Title__c, Status__c, Comments__c
            FROM Eligibility_Folder__c
            WHERE Id = :file.Folder__c
            LIMIT 1
        ];

        String flatKey = resolveFlatFolderKey(fileFolder);
        if (String.isNotBlank(flatKey)) {
            EligibilityDatalakeClient.FlatEligibilityResponsePayload payload = new EligibilityDatalakeClient.FlatEligibilityResponsePayload();
            payload.sf_id = String.valueOf(file.Candidate__c);
            payload.qualification_title = flatKey;
            payload.qualification_comment = fileFolder.Comments__c;
            payload.qualification_status = fileFolder.Status__c;

            EligibilityDatalakeClient.FilePayload fp = mapFileToPayload(file);
            payload.files = new List<EligibilityDatalakeClient.FilePayload>{ fp };

            IntegrationLogService.LogParams logParams = new IntegrationLogService.LogParams();
            logParams.integrationType = 'Outbound status file';
            logParams.requestPayload = JSON.serialize(payload);

            try {
                EligibilityDatalakeClient.CalloutResult result =
                    EligibilityDatalakeClient.postEligibilityResponseFlat(payload);
                logParams.status = result.success ? 'Success' : 'failed';
                logParams.responsePayload = result.body;
                logParams.statusCode = result.statusCode;
                logParams.errorMessage = result.success ? null : result.message;
            } catch (Exception e) {
                logParams.status = 'failed';
                logParams.errorMessage = e.getMessage();
            } finally {
                IntegrationLogService.log(logParams);
            }
            return;
        }

        Eligibility_Folder__c degreeFolder = null;
        if (fileFolder.Parent_Folder__c != null) {
            degreeFolder = [
                SELECT Id, Name, Degree_Title__c, Status__c, Comments__c
                FROM Eligibility_Folder__c
                WHERE Id = :fileFolder.Parent_Folder__c
                LIMIT 1
            ];
        }

        if (degreeFolder == null) return;

        EligibilityDatalakeClient.EligibilityResponsePayload payload = new EligibilityDatalakeClient.EligibilityResponsePayload();
        payload.sf_id = String.valueOf(file.Candidate__c);
        payload.qualification_title = String.isNotBlank(degreeFolder.Degree_Title__c) ? degreeFolder.Degree_Title__c : degreeFolder.Name;
        payload.qualification_comment = degreeFolder.Comments__c;
        payload.qualification_status = degreeFolder.Status__c;

        EligibilityDatalakeClient.FilePayload fp = mapFileToPayload(file);

        payload.files = new EligibilityDatalakeClient.FilesPayload();
        if (isCertificate(fileFolder)) {
            payload.files.certificates = new List<EligibilityDatalakeClient.FilePayload>{ fp };
            payload.files.mark_sheets = new List<EligibilityDatalakeClient.FilePayload>();
        } else {
            payload.files.mark_sheets = new List<EligibilityDatalakeClient.FilePayload>{ fp };
            payload.files.certificates = new List<EligibilityDatalakeClient.FilePayload>();
        }

        IntegrationLogService.LogParams logParams = new IntegrationLogService.LogParams();
        logParams.integrationType = 'Outbound status file';
        logParams.requestPayload = JSON.serialize(payload);

        try {
            EligibilityDatalakeClient.CalloutResult result = EligibilityDatalakeClient.postEligibilityResponse(payload);
            logParams.status = result.success ? 'Success' : 'failed';
            logParams.responsePayload = result.body;
            logParams.statusCode = result.statusCode;
            logParams.errorMessage = result.success ? null : result.message;
        } catch (Exception e) {
            logParams.status = 'failed';
            logParams.errorMessage = e.getMessage();
        } finally {
            IntegrationLogService.log(logParams);
        }
    }

    @future(callout=true)
    public static void sendForDegreeFolder(Id folderId) {
        if (folderId == null) return;

        Eligibility_Folder__c degreeFolder = [
            SELECT Id, Candidate__c, Name, Degree_Title__c, Status__c, Comments__c
            FROM Eligibility_Folder__c
            WHERE Id = :folderId
            LIMIT 1
        ];
        if (degreeFolder.Candidate__c == null) return;

        // Collect category folders and their files
        Map<String, Id> categoryIds = new Map<String, Id>();
        for (Eligibility_Folder__c cf : [
            SELECT Id, Folder_Type__c
            FROM Eligibility_Folder__c
            WHERE Parent_Folder__c = :degreeFolder.Id
        ]) {
            categoryIds.put(cf.Folder_Type__c, cf.Id);
        }

        List<Eligibility_File__c> files = [
            SELECT Id, Candidate__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                   Status__c, Comment__c, Name, File_Type__c
            FROM Eligibility_File__c
            WHERE Candidate__c = :degreeFolder.Candidate__c
              AND Folder__c IN :categoryIds.values()
        ];

        List<EligibilityDatalakeClient.FilePayload> certs = new List<EligibilityDatalakeClient.FilePayload>();
        List<EligibilityDatalakeClient.FilePayload> marks = new List<EligibilityDatalakeClient.FilePayload>();

        for (Eligibility_File__c f : files) {
            EligibilityDatalakeClient.FilePayload fp = mapFileToPayload(f);
            String folderType = getFolderType(categoryIds, f.Folder__c);
            if (folderType == 'Certificates') {
                certs.add(fp);
            } else {
                marks.add(fp);
            }
        }

        EligibilityDatalakeClient.EligibilityResponsePayload payload = new EligibilityDatalakeClient.EligibilityResponsePayload();
        payload.sf_id = String.valueOf(degreeFolder.Candidate__c);
        payload.qualification_title = String.isNotBlank(degreeFolder.Degree_Title__c) ? degreeFolder.Degree_Title__c : degreeFolder.Name;
        payload.qualification_comment = degreeFolder.Comments__c;
        payload.qualification_status = degreeFolder.Status__c;

        payload.files = new EligibilityDatalakeClient.FilesPayload();
        payload.files.certificates = certs;
        payload.files.mark_sheets = marks;

        IntegrationLogService.LogParams logParams = new IntegrationLogService.LogParams();
        logParams.integrationType = 'Outbound status file';
        logParams.requestPayload = JSON.serialize(payload);

        try {
            EligibilityDatalakeClient.CalloutResult result = EligibilityDatalakeClient.postEligibilityResponse(payload);
            logParams.status = result.success ? 'Success' : 'failed';
            logParams.responsePayload = result.body;
            logParams.statusCode = result.statusCode;
            logParams.errorMessage = result.success ? null : result.message;
        } catch (Exception e) {
            logParams.status = 'failed';
            logParams.errorMessage = e.getMessage();
        } finally {
            IntegrationLogService.log(logParams);
        }
    }

    private static EligibilityDatalakeClient.FilePayload mapFileToPayload(Eligibility_File__c f) {
        EligibilityDatalakeClient.FilePayload fp = new EligibilityDatalakeClient.FilePayload();
        fp.file_type = f.File_Format__c;
        fp.file_path = f.Storage_Key__c;
        fp.file_UUID = f.File_UUID__c;
        fp.file_comment = f.Comment__c;
        fp.file_status = f.Status__c;
        return fp;
    }

    private static Boolean isCertificate(Eligibility_Folder__c folder) {
        if (folder == null || String.isBlank(folder.Folder_Type__c)) return false;
        return folder.Folder_Type__c.toLowerCase().contains('certificate');
    }

    private static String getFolderType(Map<String, Id> typeToId, Id folderId) {
        if (folderId == null || typeToId == null) return null;
        for (String k : typeToId.keySet()) {
            if (typeToId.get(k) == folderId) {
                return k;
            }
        }
        return null;
    }

    private static String resolveFlatFolderKey(Eligibility_Folder__c folder) {
        if (folder == null) return null;
        String key = EligibilityPathParser.normalizeFlatFolderKey(folder.Folder_Type__c);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Name);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Qualification_Type__c);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Degree_Title__c);
        return key;
    }
}